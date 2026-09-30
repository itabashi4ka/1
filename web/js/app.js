/*
 * 画面の処理。計算などのロジックは core.js（InstallmentCore）にある。
 * 入力内容（患者名・支払総額など）はメモリ上だけに持ち、保存も送信もしない（仕様 9章）。
 * 保存するのは設定だけ（このブラウザの localStorage）。
 */
(function () {
  'use strict';

  const C = window.InstallmentCore;
  const DEFAULT_TEMPLATE = window.DEFAULT_TEMPLATE;
  const STORAGE_KEY = 'installment-calculator.settings.v1';
  const LOGO_MAX_BYTES = 800 * 1024;

  const $ = (id) => document.getElementById(id);
  const esc = C.escapeHTML;

  // ---------------------------------------------------------------------------
  // 状態

  let settings = loadSettings();
  let form = newForm();
  let result = null;
  let error = null;
  /** 利息総額を見せているか。起動時と、入力を変えて結果が変わったときは伏せる */
  let interestRevealed = false;
  let lastResultKey = null;

  function newForm() {
    const f = C.emptyForm(settings.defaultBonusMonths);
    f.rateText = settings.defaultRate;
    return f;
  }

  // ---------------------------------------------------------------------------
  // 設定の保存

  function loadSettings() {
    try {
      return C.normalizeSettings(JSON.parse(localStorage.getItem(STORAGE_KEY)));
    } catch {
      return C.defaultSettings();
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch (e) {
      toast('設定を保存できませんでした。ロゴ画像やテンプレートが大きすぎないか確認してください。', true);
    }
  }

  function updateSettings(patch) {
    const before = settings;
    settings = C.normalizeSettings({ ...settings, ...patch });
    saveSettings();
    applyTheme();
    if (before.rounding !== settings.rounding || before.adjustment !== settings.adjustment) recalc();
    else renderResult();
    renderRateStatus();
  }

  // ---------------------------------------------------------------------------
  // 見た目（設定 → CSS変数）

  function applyTheme() {
    const root = document.documentElement.style;
    root.setProperty('--primary', settings.themeColor);
    root.setProperty('--accent', settings.accentColor);
    root.setProperty('--base', settings.baseFontSize + 'px');
    root.setProperty('--result', settings.resultFontSize + 'px');
    const name = settings.fontName.replace(/["';{}<>\\]/g, '').trim();
    if (name) root.setProperty('--font', `"${name}", system-ui, -apple-system, "Hiragino Sans", sans-serif`);
    else root.removeProperty('--font');
    document.querySelector('meta[name="theme-color"]').setAttribute('content', settings.themeColor);
    $('note').textContent = settings.note;
  }

  // ---------------------------------------------------------------------------
  // 計算

  function recalc() {
    let key;
    if (!C.isFormReady(form)) {
      result = null;
      error = null;
      key = 'empty';
    } else {
      try {
        result = C.calculate(C.formToInput(form), settings);
        error = null;
        key = JSON.stringify(result, (k, v) => (typeof v === 'bigint' ? v.toString() : v));
      } catch (e) {
        if (!(e instanceof C.CalcError)) throw e;
        result = null;
        error = e;
        key = 'error:' + e.code;
      }
    }
    // 入力を変えて結果が変わったら、利息は自動で伏せ直す（仕様 5.3）
    if (key !== lastResultKey) interestRevealed = false;
    lastResultKey = key;
    renderResult();
  }

  // ---------------------------------------------------------------------------
  // 入力エリア

  function monthButtons(container, selected, onChange) {
    container.innerHTML = '';
    for (let m = 1; m <= 12; m++) {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = `${m}月`;
      b.setAttribute('aria-pressed', String(selected.includes(m)));
      b.addEventListener('click', () => {
        const set = new Set(selected);
        if (set.has(m)) set.delete(m); else set.add(m);
        selected = [...set].sort((a, c) => a - c);
        b.setAttribute('aria-pressed', String(set.has(m)));
        onChange(selected);
      });
      container.appendChild(b);
    }
  }

  function fillFirstMonthSelects() {
    const current = C.nextMonth().year;
    const years = [];
    for (let y = Math.min(current - 1, form.firstMonth.year); y <= Math.max(current + 5, form.firstMonth.year); y++) years.push(y);
    $('first-year').innerHTML = years.map((y) => `<option value="${y}">${y}年</option>`).join('');
    $('first-month').innerHTML = Array.from({ length: 12 }, (_, i) => `<option value="${i + 1}">${i + 1}月</option>`).join('');
  }

  /** form の内容を入力欄に反映する（起動時・クリア時） */
  function renderForm() {
    document.querySelectorAll('input[name="mode"]').forEach((r) => { r.checked = r.value === form.mode; });
    $('principal').value = form.principalText;
    $('rate').value = form.rateText;
    $('installments').value = form.installmentsText;
    $('payment').value = form.paymentText;
    $('bonus-enabled').checked = form.bonusEnabled;
    $('bonus-amount').value = form.bonusAmountText;
    $('patient').value = form.patientName;
    fillFirstMonthSelects();
    $('first-year').value = String(form.firstMonth.year);
    $('first-month').value = String(form.firstMonth.month);
    monthButtons($('bonus-months'), form.bonusMonths, (months) => { form.bonusMonths = months; recalc(); });
    renderModeFields();
    renderRateStatus();
  }

  function renderModeFields() {
    document.querySelectorAll('[data-mode]').forEach((el) => { el.hidden = el.dataset.mode !== form.mode; });
    $('bonus-fields').hidden = !form.bonusEnabled;
    $('payment-label').textContent = form.bonusEnabled ? '月額（ボーナスを除く）' : '月額';
  }

  /** 年率が既定値と違うときは強調して知らせる（仕様 7.2） */
  function renderRateStatus() {
    const differs = C.rateDiffersFromDefault(form.rateText, settings.defaultRate);
    const field = $('rate').closest('.field');
    field.classList.toggle('rate-differs', differs);
    $('rate-message').textContent = differs
      ? `⚠ 既定値（${settings.defaultRate}%）と異なります`
      : '✓ 既定の年率';
    $('rate-buttons').hidden = !differs;
    $('btn-rate-default').disabled = C.rateForDefault(form.rateText) == null;
  }

  function bindInputs() {
    const text = (id, key, after) => $(id).addEventListener('input', (e) => {
      form[key] = e.target.value;
      if (after) after();
      recalc();
    });
    text('principal', 'principalText');
    text('rate', 'rateText', renderRateStatus);
    text('installments', 'installmentsText');
    text('payment', 'paymentText');
    text('bonus-amount', 'bonusAmountText');
    // 患者名は計算に使わないので再計算しない（利息も伏せ直さない）
    $('patient').addEventListener('input', (e) => { form.patientName = e.target.value; });

    document.querySelectorAll('input[name="mode"]').forEach((r) => r.addEventListener('change', () => {
      form.mode = r.value;
      renderModeFields();
      recalc();
    }));
    $('bonus-enabled').addEventListener('change', (e) => {
      form.bonusEnabled = e.target.checked;
      renderModeFields();
      recalc();
    });
    const firstMonthChanged = () => {
      form.firstMonth = { year: Number($('first-year').value), month: Number($('first-month').value) };
      recalc();
    };
    $('first-year').addEventListener('change', firstMonthChanged);
    $('first-month').addEventListener('change', firstMonthChanged);

    $('btn-rate-reset').addEventListener('click', () => {
      form.rateText = settings.defaultRate;
      $('rate').value = form.rateText;
      renderRateStatus();
      recalc();
    });
    $('btn-rate-default').addEventListener('click', () => {
      const value = C.rateForDefault(form.rateText);
      if (value == null) return toast(new C.CalcError('invalidRate').message, true);
      updateSettings({ defaultRate: value });
      toast(`既定の年率を ${value}% にしました`);
    });

    $('btn-clear').addEventListener('click', () => {
      const mode = form.mode;
      form = newForm();
      form.mode = mode;
      interestRevealed = false;
      renderForm();
      recalc();
      $('principal').focus();
    });
    $('btn-interest').addEventListener('click', () => {
      interestRevealed = !interestRevealed;
      renderResult();
    });
  }

  // ---------------------------------------------------------------------------
  // 結果エリア

  function renderResult() {
    $('error').hidden = !error;
    $('error').textContent = error ? error.message : '';
    $('result').hidden = !result;
    $('placeholder').hidden = !!(result || error);
    $('placeholder').textContent = `支払総額・年率・${form.mode === 'installments' ? '分割回数' : '月額'}を入力してください。`;
    $('btn-export').disabled = !result;
    if (!result) return;

    const r = result;
    const yen = C.formatYen;
    const first = r.schedule[0];
    const last = r.schedule[r.schedule.length - 1];
    const bonus = r.input.bonus;

    // [見出し, 値, 強調の種類]  strong: 太字 / result: 太字・大きく（結果の文字サイズ）
    const rows = [
      ['元本', `${yen(r.input.principal)} 円`, 'strong'],
      ['年率', `${C.formatRate(r.input.rate)} %`],
      ['分割回数', `${r.installments} 回`, 'result'],
      ['月々のお支払い', `${yen(r.monthlyPayment)} 円`, 'result'],
    ];
    if (bonus && r.totalBonus > 0) rows.push([`ボーナス月加算（${C.formatMonths(bonus.months)}）`, `${yen(bonus.amount)} 円`]);
    rows.push(
      ['お支払い期間', `${C.formatMonth(first.month)} 〜 ${C.formatMonth(last.month)}`],
      ['お支払い額合計', `${yen(r.totalPayment)} 円`],
    );
    $('summary-table').innerHTML = '<tbody>' + rows.map(([th, td, cls]) =>
      `<tr${cls ? ` class="${cls}"` : ''}><th scope="row">${esc(th)}</th><td>${esc(td)}</td></tr>`).join('') + '</tbody>';

    $('interest-value').textContent = interestRevealed ? `${yen(r.totalInterest)}円` : `${settings.interestMask}円`;
    $('btn-interest').textContent = interestRevealed ? '利息総額を隠す' : '利息総額を表示';
    $('btn-interest').setAttribute('aria-pressed', String(interestRevealed));

    // 画面のスケジュール表は 回・支払月・支払額・（うちボーナス）・残高
    const showBonus = r.totalBonus > 0;
    const head = `<thead><tr><th>回</th><th>支払月</th><th>支払額</th>${showBonus ? '<th>うちボーナス</th>' : ''}<th>残高</th></tr></thead>`;
    const body = r.schedule.map((row) => `<tr${row.bonus > 0 ? ' class="bonus-row"' : ''}>`
      + `<td>${row.no}</td><td>${C.formatMonth(row.month)}</td><td>${yen(row.payment)}</td>`
      + (showBonus ? `<td>${row.bonus > 0 ? yen(row.bonus) : ''}</td>` : '')
      + `<td>${yen(row.balance)}</td></tr>`).join('');
    $('schedule-table').innerHTML = head + '<tbody>' + body + '</tbody>';
  }

  // ---------------------------------------------------------------------------
  // 支払い表の出力（仕様 6章）

  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  function templateHTML(id) {
    const custom = settings.templates.find((t) => t.id === id);
    return custom ? custom.html : DEFAULT_TEMPLATE;
  }

  function templateOptions(select, selectedId) {
    const options = [{ id: C.DEFAULT_TEMPLATE_ID, name: '既定のテンプレート' }, ...settings.templates];
    select.innerHTML = options.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
    select.value = options.some((t) => t.id === selectedId) ? selectedId : C.DEFAULT_TEMPLATE_ID;
  }

  function renderPaymentTable() {
    if (!result) return '';
    const context = C.buildTemplateContext(result, settings, form.patientName.trim(), $('export-interest').checked);
    return C.renderTemplate(templateHTML($('export-template').value), context);
  }

  function refreshPreview() {
    $('export-preview').srcdoc = renderPaymentTable();
  }

  function openExport() {
    if (!result) return;
    templateOptions($('export-template'), settings.templateId);
    $('export-interest').checked = false; // 利息は既定で出さない
    $('print-hint').textContent = isIOS
      ? '印刷画面で「プリント」を選ぶとAirPrintで印刷できます。PDFにするには、印刷画面の共有ボタン →「ファイルに保存」を選びます。'
      : '印刷画面の「PDF」（Chromeは送信先「PDFに保存」）を選ぶとPDFで保存できます。保存先はその場で選べます。';
    refreshPreview();
    $('export-dialog').showModal();
  }

  function printPaymentTable() {
    const html = renderPaymentTable();
    if (isIOS) {
      // iPad の Safari は iframe だけを印刷できないため、別のタブで開いて印刷する
      const w = window.open('', '_blank');
      if (!w) return toast('新しいタブを開けませんでした。ポップアップを許可してください。', true);
      w.document.open();
      w.document.write(html);
      w.document.close();
      w.addEventListener('load', () => setTimeout(() => w.print(), 300));
      setTimeout(() => { try { w.print(); } catch { /* 読み込み後の print に任せる */ } }, 1200);
      return;
    }
    const frame = $('export-preview');
    const doPrint = () => { frame.contentWindow.focus(); frame.contentWindow.print(); };
    if (frame.srcdoc !== html) {
      frame.addEventListener('load', doPrint, { once: true });
      frame.srcdoc = html;
    } else {
      doPrint();
    }
  }

  function openInNewTab() {
    const url = URL.createObjectURL(new Blob([renderPaymentTable()], { type: 'text/html' }));
    const w = window.open(url, '_blank');
    if (!w) toast('新しいタブを開けませんでした。ポップアップを許可してください。', true);
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }

  function bindExport() {
    $('btn-export').addEventListener('click', openExport);
    $('export-template').addEventListener('change', refreshPreview);
    $('export-interest').addEventListener('change', refreshPreview);
    $('btn-print').addEventListener('click', printPaymentTable);
    $('btn-open-tab').addEventListener('click', openInNewTab);
    // 閉じたらプレビューを消す（患者名を画面に残さない）
    $('export-dialog').addEventListener('close', () => { $('export-preview').srcdoc = ''; });
  }

  // ---------------------------------------------------------------------------
  // 設定画面（仕様 7章）

  function renderSettingsForm() {
    document.querySelectorAll('[data-setting]').forEach((el) => {
      el.value = settings[el.dataset.setting];
    });
    document.querySelectorAll('[data-output]').forEach((el) => {
      el.textContent = settings[el.dataset.output] + 'px';
    });
    $('setting-default-rate').value = settings.defaultRate;
    $('logo-preview').hidden = !settings.logo;
    $('btn-logo-remove').hidden = !settings.logo;
    if (settings.logo) $('logo-preview').src = settings.logo; else $('logo-preview').removeAttribute('src');
    templateOptions($('setting-template'), settings.templateId);
    $('btn-template-delete').disabled = settings.templateId === C.DEFAULT_TEMPLATE_ID;
    monthButtons($('default-bonus-months'), settings.defaultBonusMonths, (months) => updateSettings({ defaultBonusMonths: months }));
  }

  function download(filename, content, type) {
    const url = URL.createObjectURL(new Blob([content], { type }));
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  }

  function readFile(input, as) {
    return new Promise((resolve, reject) => {
      const file = input.files && input.files[0];
      input.value = '';
      if (!file) return reject(new Error('ファイルが選ばれていません'));
      const reader = new FileReader();
      reader.onload = () => resolve({ file, data: reader.result });
      reader.onerror = () => reject(reader.error);
      if (as === 'dataURL') reader.readAsDataURL(file); else reader.readAsText(file, 'utf-8');
    });
  }

  function bindSettings() {
    $('btn-settings').addEventListener('click', () => {
      renderSettingsForm();
      $('settings-dialog').showModal();
    });

    $('setting-rounding').innerHTML = Object.entries(C.ROUNDING_RULES).map(([k, v]) => `<option value="${k}">${v}</option>`).join('');
    $('setting-adjustment').innerHTML = Object.entries(C.ADJUSTMENTS).map(([k, v]) => `<option value="${k}">${v}</option>`).join('');

    document.querySelectorAll('[data-setting]').forEach((el) => {
      el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        const value = el.dataset.type === 'number' ? Number(el.value) : el.value;
        updateSettings({ [el.dataset.setting]: value });
        const out = document.querySelector(`[data-output="${el.dataset.setting}"]`);
        if (out) out.textContent = value + 'px';
      });
    });

    const saveDefaultRate = () => {
      const value = C.rateForDefault($('setting-default-rate').value);
      if (value == null) return toast(new C.CalcError('invalidRate').message, true);
      updateSettings({ defaultRate: value });
      $('setting-default-rate').value = value;
      toast(`既定の年率を ${value}% にしました`);
    };
    $('btn-save-default-rate').addEventListener('click', saveDefaultRate);
    $('setting-default-rate').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveDefaultRate(); });

    $('logo-file').addEventListener('change', async (e) => {
      try {
        const { file, data } = await readFile(e.target, 'dataURL');
        if (file.size > LOGO_MAX_BYTES) return toast('画像が大きすぎます（800KBまで）。小さくしてから選んでください。', true);
        updateSettings({ logo: data });
        renderSettingsForm();
      } catch (err) { toast('画像を読み込めませんでした: ' + err.message, true); }
    });
    $('btn-logo-remove').addEventListener('click', () => { updateSettings({ logo: '' }); renderSettingsForm(); });

    $('setting-template').addEventListener('change', (e) => { updateSettings({ templateId: e.target.value }); renderSettingsForm(); });
    $('template-file').addEventListener('change', async (e) => {
      try {
        const { file, data } = await readFile(e.target, 'text');
        if (!data.includes(C.ROW_START)) toast('注意: テンプレートに <!-- ROW_START --> がないため、スケジュール表は出力されません。');
        const existing = settings.templates.find((t) => t.name === file.name);
        const id = existing ? existing.id : 't' + Date.now().toString(36);
        const templates = settings.templates.filter((t) => t.id !== id).concat({ id, name: file.name, html: data });
        updateSettings({ templates, templateId: id });
        renderSettingsForm();
        toast(`テンプレート「${file.name}」を読み込みました`);
      } catch (err) { toast('テンプレートを読み込めませんでした: ' + err.message, true); }
    });
    $('btn-template-delete').addEventListener('click', () => {
      const t = settings.templates.find((x) => x.id === settings.templateId);
      if (!t || !confirm(`テンプレート「${t.name}」を削除しますか？`)) return;
      updateSettings({ templates: settings.templates.filter((x) => x.id !== t.id), templateId: C.DEFAULT_TEMPLATE_ID });
      renderSettingsForm();
    });
    $('btn-template-download').addEventListener('click', () => download('default.html', DEFAULT_TEMPLATE, 'text/html'));

    $('btn-settings-export').addEventListener('click', () => {
      download('installment-calculator-settings.json', JSON.stringify(settings, null, 2), 'application/json');
    });
    $('settings-file').addEventListener('change', async (e) => {
      try {
        const { data } = await readFile(e.target, 'text');
        const raw = JSON.parse(data);
        settings = C.normalizeSettings(raw);
        saveSettings();
        applyTheme();
        form.rateText = settings.defaultRate;
        $('rate').value = form.rateText;
        renderSettingsForm();
        renderRateStatus();
        recalc();
        toast('設定を読み込みました');
      } catch (err) { toast('設定を読み込めませんでした: ' + err.message, true); }
    });
    $('btn-settings-reset').addEventListener('click', () => {
      if (!confirm('設定を初期状態に戻しますか？（ロゴ・読み込んだテンプレートも消えます）')) return;
      settings = C.defaultSettings();
      saveSettings();
      applyTheme();
      renderSettingsForm();
      renderRateStatus();
      recalc();
    });
  }

  // ---------------------------------------------------------------------------
  // 共通

  let toastTimer;
  function toast(message, isError = false) {
    const el = $('toast');
    el.textContent = message;
    el.classList.toggle('error', isError);
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, isError ? 6000 : 3000);
  }

  document.querySelectorAll('dialog [data-close]').forEach((b) => b.addEventListener('click', () => b.closest('dialog').close()));
  // 背景をクリックしたら閉じる
  document.querySelectorAll('dialog').forEach((d) => d.addEventListener('click', (e) => { if (e.target === d) d.close(); }));

  applyTheme();
  bindInputs();
  bindExport();
  bindSettings();
  renderForm();
  recalc();

  // ホスティング（https）したときは、オフラインでも開けるようにする
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
})();
