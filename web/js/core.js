/*
 * 分割払い計算のコア（計算・入力の解釈・表示の書式・テンプレート差し込み・設定）。
 * 画面（DOM）には依存しない。ブラウザでは window.InstallmentCore、Node.js では require() で使う。
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.InstallmentCore = api;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /** これを超える年率は入力ミスとみなす（%） */
  const MAX_RATE_PERCENT = 30;
  /** 分割回数の上限（50年） */
  const MAX_INSTALLMENTS = 600;
  /** 年率は 1/10000 % 単位の整数（BigInt）で持ち、利息計算を誤差なく行う */
  const RATE_SCALE = 10000n;
  const RATE_DECIMALS = 4;

  // ---------------------------------------------------------------------------
  // エラー

  const MESSAGES = {
    invalidPrincipal: '支払総額は1円以上の整数で入力してください。',
    invalidRate: `年率は0〜${MAX_RATE_PERCENT}%の範囲で入力してください（小数は${RATE_DECIMALS}桁まで）。`,
    invalidInstallments: '分割回数は1以上の整数で入力してください。',
    invalidMonthlyPayment: '月額は1円以上の整数で入力してください。',
    invalidBonusAmount: 'ボーナス加算額は0円以上の整数で入力してください。',
    invalidBonusMonth: 'ボーナス月は1〜12月から選んでください。',
    cannotRepay: '月額（およびボーナス）が毎月の利息以下のため、完済できません。',
    tooManyInstallments: `分割回数が上限（${MAX_INSTALLMENTS}回）を超えます。月額を増やしてください。`,
    bonusTooLarge: 'ボーナス加算額が大きすぎるため、月額を求められません。',
  };

  class CalcError extends Error {
    constructor(code) {
      super(MESSAGES[code] || code);
      this.name = 'CalcError';
      this.code = code;
    }
  }

  // ---------------------------------------------------------------------------
  // 端数処理

  const ROUNDING_RULES = { down: '切り捨て', up: '切り上げ', nearest: '四捨五入' };
  const ADJUSTMENTS = { last: '最終回で調整', first: '初回で調整' };

  /** 0以上の num / den を円に丸める（BigInt） */
  function roundRatio(num, den, rule) {
    let q;
    switch (rule) {
      case 'up': q = (num + den - 1n) / den; break;
      case 'nearest': q = (2n * num + den) / (2n * den); break;
      default: q = num / den;
    }
    return Number(q);
  }

  function roundNumber(value, rule) {
    switch (rule) {
      case 'up': return Math.ceil(value - 1e-9);
      case 'nearest': return Math.round(value);
      default: return Math.floor(value + 1e-9);
    }
  }

  // ---------------------------------------------------------------------------
  // 入力の解釈（全角数字・カンマ・「円」「%」・空白を許す）

  function normalizeNumberText(text) {
    let out = '';
    for (const ch of String(text ?? '')) {
      const code = ch.codePointAt(0);
      if (code >= 0xff10 && code <= 0xff19) out += String.fromCharCode(code - 0xff10 + 0x30);
      else if (ch === '．') out += '.';
      else if (ch === '－' || ch === '−') out += '-';
      else if (',，、 　円%％'.includes(ch)) continue;
      else out += ch;
    }
    return out;
  }

  /** 整数。小数や文字を含むものは null */
  function parseInteger(text) {
    const s = normalizeNumberText(text);
    if (!/^-?\d+$/.test(s)) return null;
    const n = Number(s);
    return Number.isSafeInteger(n) ? n : null;
  }

  /** 年率の文字列 → 1/10000 % 単位の BigInt。解釈できなければ null */
  function parseRate(text) {
    const s = normalizeNumberText(text);
    const m = /^(-?)(\d*)(?:\.(\d*))?$/.exec(s);
    if (!m || (m[2] === '' && (m[3] ?? '') === '')) return null;
    const frac = m[3] ?? '';
    if (frac.length > RATE_DECIMALS) return null;
    const scaled = BigInt(m[2] || '0') * RATE_SCALE + BigInt((frac + '0000').slice(0, RATE_DECIMALS));
    return m[1] === '-' ? -scaled : scaled;
  }

  /** 1/10000 % 単位 → "3", "2.5" */
  function formatRate(scaled) {
    const neg = scaled < 0n;
    const abs = neg ? -scaled : scaled;
    const whole = abs / RATE_SCALE;
    let frac = String(abs % RATE_SCALE).padStart(RATE_DECIMALS, '0').replace(/0+$/, '');
    return (neg ? '-' : '') + whole + (frac ? '.' + frac : '');
  }

  // ---------------------------------------------------------------------------
  // 年月

  function addMonths(ym, months) {
    const index = ym.year * 12 + (ym.month - 1) + months;
    return { year: Math.floor(index / 12), month: (index % 12) + 1 };
  }

  function nextMonth(date = new Date()) {
    return addMonths({ year: date.getFullYear(), month: date.getMonth() + 1 }, 1);
  }

  // ---------------------------------------------------------------------------
  // 計算

  function bonusAddition(bonus, ym) {
    return bonus && bonus.amount > 0 && bonus.months.includes(ym.month) ? bonus.amount : 0;
  }

  function isBonusActive(bonus) {
    return !!bonus && bonus.amount > 0 && bonus.months.length > 0;
  }

  function validate(input) {
    if (!Number.isSafeInteger(input.principal) || input.principal <= 0) throw new CalcError('invalidPrincipal');
    if (typeof input.rate !== 'bigint' || input.rate < 0n || input.rate > BigInt(MAX_RATE_PERCENT) * RATE_SCALE) {
      throw new CalcError('invalidRate');
    }
    if (input.mode === 'installments') {
      if (!Number.isSafeInteger(input.value) || input.value < 1) throw new CalcError('invalidInstallments');
      if (input.value > MAX_INSTALLMENTS) throw new CalcError('tooManyInstallments');
    } else {
      if (!Number.isSafeInteger(input.value) || input.value < 1) throw new CalcError('invalidMonthlyPayment');
    }
    if (input.bonus) {
      if (!Number.isSafeInteger(input.bonus.amount) || input.bonus.amount < 0) throw new CalcError('invalidBonusAmount');
      if (!input.bonus.months.every((m) => Number.isInteger(m) && m >= 1 && m <= 12)) throw new CalcError('invalidBonusMonth');
    }
  }

  /** 月ごとの残高シミュレーション */
  function makeSimulator(input, rule) {
    const bonus = input.bonus || { amount: 0, months: [] };
    const den = 1200n * RATE_SCALE;
    const interestOn = (balance) => (balance <= 0 ? 0 : roundRatio(BigInt(balance) * input.rate, den, rule));
    const monthAt = (k) => addMonths(input.firstMonth, k - 1);

    function finalRow(k, month, due, interest, bonusAdd) {
      return { no: k, month, payment: due, bonus: Math.min(bonusAdd, due), principal: due - interest, interest, balance: 0 };
    }

    /** 回数を決めて支払う（モード②）。最終回は残高に合わせて調整。途中で完済できたらそこで終わる */
    function run(regular, n, firstPayment) {
      const rows = [];
      let balance = input.principal;
      for (let k = 1; k <= n; k++) {
        const month = monthAt(k);
        const interest = interestOn(balance);
        const bonusAdd = bonusAddition(bonus, month);
        const base = k === 1 && firstPayment != null ? firstPayment : regular;
        const due = balance + interest;
        if (k === n || base + bonusAdd >= due) {
          rows.push(finalRow(k, month, due, interest, bonusAdd));
          break;
        }
        const payment = base + bonusAdd;
        balance -= payment - interest;
        rows.push({ no: k, month, payment, bonus: bonusAdd, principal: payment - interest, interest, balance });
      }
      return rows;
    }

    /**
     * 月額を決めて完済まで支払う（モード①）。
     * 月額を円に丸めたことによる残り（1回あたり1円未満の積み重ね）しか残らない場合は、
     * 新しい回を作らずその回に合算する。これで②の月額を①に入れると同じ回数に戻る。
     */
    function runUntilRepaid(regular) {
      const rows = [];
      let balance = input.principal;
      let checkpoint = balance;
      const growth = 1 + Number(input.rate) / Number(den);
      let slack = 0;

      if (!isBonusActive(bonus) && regular <= interestOn(balance)) throw new CalcError('cannotRepay');

      for (let k = 1; ; k++) {
        if (k > MAX_INSTALLMENTS) throw new CalcError('tooManyInstallments');
        const month = monthAt(k);
        const interest = interestOn(balance);
        const bonusAdd = bonusAddition(bonus, month);
        const due = balance + interest;
        let payment = regular + bonusAdd;
        if (payment >= due) {
          rows.push(finalRow(k, month, due, interest, bonusAdd));
          return rows;
        }
        balance -= payment - interest;
        slack = slack * growth + 1;
        const tolerance = Math.min(Math.floor(slack), Math.floor(regular / 2));
        if (balance <= tolerance) {
          payment += balance;
          balance = 0;
        }
        rows.push({ no: k, month, payment, bonus: bonusAdd, principal: payment - interest, interest, balance });
        if (balance === 0) return rows;
        // 1年ごとに残高が減っているか確認（ボーナス月の支払いも含めて判定）
        if (k % 12 === 0) {
          if (balance >= checkpoint) throw new CalcError('cannotRepay');
          checkpoint = balance;
        }
      }
    }

    return { run, runUntilRepaid };
  }

  /**
   * n回ちょうどで残高が0になる月額（ボーナスを除く）。
   * A = Σ (P + B_k) / (1 + r)^k は P の1次式なので直接解ける（ボーナスなしなら公式と一致）。
   */
  function solveMonthlyPayment(input, n, rule) {
    const r = Number(input.rate) / Number(1200n * RATE_SCALE);
    let annuity = 0;
    let bonusValue = 0;
    let discount = 1;
    for (let k = 1; k <= n; k++) {
      discount /= 1 + r;
      annuity += discount;
      bonusValue += bonusAddition(input.bonus, addMonths(input.firstMonth, k - 1)) * discount;
    }
    const payment = roundNumber((input.principal - bonusValue) / annuity, rule);
    if (payment < 1) throw new CalcError(isBonusActive(input.bonus) ? 'bonusTooLarge' : 'invalidPrincipal');
    return payment;
  }

  /** 差額を初回で調整：最終回がなるべく通常額と同じになるよう初回の額を決める */
  function adjustFirstPayment(sim, input, regular, n, fallback) {
    const last = fallback[fallback.length - 1];
    if (!last || fallback.length !== n) return fallback;
    const expectedLast = regular + last.bonus;
    const growth = Math.pow(1 + Number(input.rate) / Number(1200n * RATE_SCALE), n - 1);
    const estimate = regular + Math.round((last.payment - expectedLast) / growth);
    let best = fallback;
    let bestGap = Math.abs(last.payment - expectedLast);
    for (let first = estimate - 3; first <= estimate + 3; first++) {
      if (first < 1) continue;
      const candidate = sim.run(regular, n, first);
      const cl = candidate[candidate.length - 1];
      if (candidate.length !== n) continue;
      const gap = Math.abs(cl.payment - expectedLast);
      const bestLast = best[best.length - 1].payment;
      if (gap < bestGap || (gap === bestGap && cl.payment <= expectedLast && bestLast > expectedLast)) {
        best = candidate;
        bestGap = gap;
      }
    }
    return best;
  }

  /**
   * 計算する。
   * @param input { principal, rate(BigInt, 1/10000%), mode: 'installments'|'payment', value, bonus: {amount, months}|null, firstMonth: {year, month} }
   * @param options { rounding: 'down'|'up'|'nearest', adjustment: 'last'|'first' }
   */
  function calculate(input, options = {}) {
    const rule = options.rounding || 'down';
    validate(input);
    const sim = makeSimulator(input, rule);
    let monthlyPayment;
    let schedule;
    if (input.mode === 'installments') {
      monthlyPayment = solveMonthlyPayment(input, input.value, rule);
      schedule = sim.run(monthlyPayment, input.value);
      if (options.adjustment === 'first' && input.value > 1) {
        schedule = adjustFirstPayment(sim, input, monthlyPayment, input.value, schedule);
      }
    } else {
      monthlyPayment = input.value;
      schedule = sim.runUntilRepaid(monthlyPayment);
    }
    return makeResult(input, monthlyPayment, schedule);
  }

  function makeResult(input, monthlyPayment, schedule) {
    const sum = (key) => schedule.reduce((a, row) => a + row[key], 0);
    const totalPayment = sum('payment');
    return {
      input,
      monthlyPayment,
      schedule,
      installments: schedule.length,
      totalPayment,
      totalInterest: totalPayment - input.principal,
      totalBonus: sum('bonus'),
      firstPayment: schedule[0].payment,
      lastPayment: schedule[schedule.length - 1].payment,
    };
  }

  /** 参考: ボーナスなしの月額の公式（丸める前） */
  function monthlyPaymentFormula(principal, monthlyRate, n) {
    if (monthlyRate === 0) return principal / n;
    return (principal * monthlyRate) / (1 - Math.pow(1 + monthlyRate, -n));
  }

  /** 参考: ボーナスなしの回数の公式（切り上げ前）。完済不能なら null */
  function installmentsFormula(principal, monthlyRate, payment) {
    if (monthlyRate === 0) return principal / payment;
    const x = 1 - (principal * monthlyRate) / payment;
    return x > 0 ? -Math.log(x) / Math.log(1 + monthlyRate) : null;
  }

  // ---------------------------------------------------------------------------
  // 入力フォーム → 計算の入力

  function emptyForm(defaultBonusMonths = [6, 12], date = new Date()) {
    return {
      mode: 'installments', // 'installments'（② 回数から）| 'payment'（① 月額から）
      principalText: '',
      rateText: '',
      installmentsText: '',
      paymentText: '',
      bonusEnabled: false,
      bonusAmountText: '',
      bonusMonths: [...defaultBonusMonths],
      firstMonth: nextMonth(date),
      patientName: '',
    };
  }

  function isFormReady(form) {
    const main = form.mode === 'installments' ? form.installmentsText : form.paymentText;
    return [form.principalText, form.rateText, main].every((t) => String(t ?? '').trim() !== '');
  }

  function formToInput(form) {
    const principal = parseInteger(form.principalText);
    if (principal == null || principal <= 0) throw new CalcError('invalidPrincipal');
    const rate = parseRate(form.rateText);
    if (rate == null) throw new CalcError('invalidRate');
    let value;
    if (form.mode === 'installments') {
      value = parseInteger(form.installmentsText);
      if (value == null || value < 1) throw new CalcError('invalidInstallments');
    } else {
      value = parseInteger(form.paymentText);
      if (value == null || value < 1) throw new CalcError('invalidMonthlyPayment');
    }
    let bonus = null;
    if (form.bonusEnabled) {
      const text = String(form.bonusAmountText ?? '').trim();
      const amount = text === '' ? 0 : parseInteger(text);
      if (amount == null || amount < 0) throw new CalcError('invalidBonusAmount');
      bonus = { amount, months: [...form.bonusMonths].sort((a, b) => a - b) };
    }
    const input = { principal, rate, mode: form.mode, value, bonus, firstMonth: { ...form.firstMonth } };
    validate(input);
    return input;
  }

  // ---------------------------------------------------------------------------
  // 表示の書式

  function formatYen(value) {
    const s = String(Math.abs(value)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return value < 0 ? '-' + s : s;
  }
  const formatMonth = (ym) => `${ym.year}年${ym.month}月`;
  const formatMonths = (months) => [...months].sort((a, b) => a - b).map((m) => `${m}月`).join('・');
  const formatDate = (d) => `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;

  // ---------------------------------------------------------------------------
  // HTMLテンプレート
  //  - {{key}} を値に置換（HTMLエスケープ）。未知のキーはそのまま残す
  //  - <!-- ROW_START --> 〜 <!-- ROW_END --> を1行分のひな形として回数分複製
  //  - data-show="<section>" の要素は、そのセクションが非表示なら要素ごと除去

  const ROW_START = '<!-- ROW_START -->';
  const ROW_END = '<!-- ROW_END -->';
  const VOID_ELEMENTS = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);

  function escapeHTML(text) {
    return String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  }

  function replacePlaceholders(html, values) {
    return html.replace(/\{\{([^{}]*)\}\}/g, (whole, key) => {
      const k = key.trim();
      return Object.prototype.hasOwnProperty.call(values, k) ? escapeHTML(values[k]) : whole;
    });
  }

  function expandRows(html, rows) {
    let out = '';
    let rest = html;
    for (;;) {
      const start = rest.indexOf(ROW_START);
      if (start < 0) break;
      const end = rest.indexOf(ROW_END, start + ROW_START.length);
      if (end < 0) break;
      out += rest.slice(0, start);
      const tpl = rest.slice(start + ROW_START.length, end);
      for (const row of rows) out += replacePlaceholders(tpl, row);
      rest = rest.slice(end + ROW_END.length);
    }
    return out + rest;
  }

  function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function removeElements(html, section) {
    const open = new RegExp(`<([A-Za-z][A-Za-z0-9-]*)\\b[^>]*\\bdata-show\\s*=\\s*["']${escapeRegExp(section)}["'][^>]*>`);
    let result = html;
    let from = 0;
    for (;;) {
      const m = open.exec(result.slice(from));
      if (!m) break;
      const startIdx = from + m.index;
      const tag = m[1].toLowerCase();
      let endIdx = startIdx + m[0].length;
      if (!m[0].endsWith('/>') && !VOID_ELEMENTS.has(tag)) {
        const re = new RegExp(`<(/?)${escapeRegExp(tag)}\\b[^>]*?(/?)>`, 'gi');
        re.lastIndex = endIdx;
        let depth = 1;
        let t;
        while ((t = re.exec(result))) {
          if (t[1]) {
            if (--depth === 0) { endIdx = t.index + t[0].length; break; }
          } else if (!t[2]) depth++;
        }
      }
      result = result.slice(0, startIdx) + result.slice(endIdx);
      from = startIdx;
    }
    return result;
  }

  function renderTemplate(template, context) {
    let html = template;
    for (const section of [...context.hidden].sort()) html = removeElements(html, section);
    html = expandRows(html, context.rows);
    return replacePlaceholders(html, context.values);
  }

  /** 計算結果・設定から差し込む値を作る。金額はカンマ区切りの数字のみ（「円」はテンプレート側） */
  function buildTemplateContext(result, settings, patientName, showInterest, issueDate = new Date()) {
    const input = result.input;
    const bonus = isBonusActive(input.bonus) && result.totalBonus > 0 ? input.bonus : null;
    const first = result.schedule[0];
    const last = result.schedule[result.schedule.length - 1];
    const values = {
      clinic_name: settings.clinicName,
      patient_name: patientName,
      issue_date: formatDate(issueDate),
      principal: formatYen(input.principal),
      annual_rate: formatRate(input.rate),
      installments: String(result.installments),
      monthly_payment: formatYen(result.monthlyPayment),
      first_payment: formatYen(result.firstPayment),
      last_payment: formatYen(result.lastPayment),
      bonus_amount: bonus ? formatYen(bonus.amount) : '',
      bonus_months: bonus ? formatMonths(bonus.months) : '',
      total_bonus: formatYen(result.totalBonus),
      total_payment: formatYen(result.totalPayment),
      total_interest: showInterest ? formatYen(result.totalInterest) : '',
      first_month: formatMonth(first.month),
      last_month: formatMonth(last.month),
      note: settings.note,
      theme_color: settings.themeColor,
      accent_color: settings.accentColor,
      font_family: settings.fontName,
      logo: settings.logo || '',
    };
    const rows = result.schedule.map((row) => ({
      'row.no': String(row.no),
      'row.month': formatMonth(row.month),
      'row.payment': formatYen(row.payment),
      'row.bonus': row.bonus > 0 ? formatYen(row.bonus) : '',
      'row.principal': formatYen(row.principal),
      'row.interest': showInterest ? formatYen(row.interest) : '',
      'row.balance': formatYen(row.balance),
    }));
    const hidden = new Set();
    if (!showInterest) hidden.add('interest');
    if (!bonus) hidden.add('bonus');
    if (!settings.logo) hidden.add('logo');
    if (!String(patientName ?? '').trim()) hidden.add('patient');
    return { values, rows, hidden };
  }

  // ---------------------------------------------------------------------------
  // 設定（患者に関する項目は入れないこと）

  const SETTINGS_VERSION = 1;
  const DEFAULT_TEMPLATE_ID = 'default';

  function defaultSettings() {
    return {
      version: SETTINGS_VERSION,
      clinicName: '〇〇歯科クリニック',
      logo: '', // data URL
      themeColor: '#2F6F8F',
      accentColor: '#E07A2E',
      fontName: '',
      baseFontSize: 17,
      resultFontSize: 56,
      note: '概算です。実際の条件は契約内容によります。',
      interestMask: '●●●',
      rounding: 'down',
      adjustment: 'last',
      defaultRate: '0', // 既定の年率（%、文字列で正確に保持）
      defaultBonusMonths: [6, 12],
      templateId: DEFAULT_TEMPLATE_ID,
      templates: [], // 自作テンプレート [{ id, name, html }]
    };
  }

  /** 読み込んだ設定を検証し、欠けた項目・不正な値は既定値で補う */
  function normalizeSettings(raw) {
    const d = defaultSettings();
    if (!raw || typeof raw !== 'object') return d;
    const s = { ...d };
    const str = (k) => { if (typeof raw[k] === 'string') s[k] = raw[k]; };
    const num = (k, min, max) => { if (typeof raw[k] === 'number' && raw[k] >= min && raw[k] <= max) s[k] = raw[k]; };
    const color = (k) => { if (typeof raw[k] === 'string' && /^#[0-9a-fA-F]{6}$/.test(raw[k])) s[k] = raw[k]; };
    ['clinicName', 'fontName', 'note', 'interestMask'].forEach(str);
    if (typeof raw.logo === 'string' && (raw.logo === '' || raw.logo.startsWith('data:image/'))) s.logo = raw.logo;
    color('themeColor');
    color('accentColor');
    num('baseFontSize', 10, 40);
    num('resultFontSize', 20, 160);
    if (raw.rounding in ROUNDING_RULES) s.rounding = raw.rounding;
    if (raw.adjustment in ADJUSTMENTS) s.adjustment = raw.adjustment;
    const rate = parseRate(raw.defaultRate);
    if (rate != null && rate >= 0n && rate <= BigInt(MAX_RATE_PERCENT) * RATE_SCALE) s.defaultRate = formatRate(rate);
    if (Array.isArray(raw.defaultBonusMonths)) {
      s.defaultBonusMonths = [...new Set(raw.defaultBonusMonths.filter((m) => Number.isInteger(m) && m >= 1 && m <= 12))].sort((a, b) => a - b);
    }
    if (Array.isArray(raw.templates)) {
      s.templates = raw.templates
        .filter((t) => t && typeof t.id === 'string' && typeof t.name === 'string' && typeof t.html === 'string')
        .map((t) => ({ id: t.id, name: t.name, html: t.html }));
    }
    if (typeof raw.templateId === 'string' && (raw.templateId === DEFAULT_TEMPLATE_ID || s.templates.some((t) => t.id === raw.templateId))) {
      s.templateId = raw.templateId;
    }
    return s;
  }

  // ---------------------------------------------------------------------------
  // 年率の既定値（入力欄が既定値と違うか）

  function rateDiffersFromDefault(rateText, defaultRate) {
    const value = parseRate(rateText);
    return value == null || value !== parseRate(defaultRate);
  }

  /** 「この値を既定にする」で保存できる値（正規化した文字列）。不正なら null */
  function rateForDefault(rateText) {
    const value = parseRate(rateText);
    if (value == null || value < 0n || value > BigInt(MAX_RATE_PERCENT) * RATE_SCALE) return null;
    return formatRate(value);
  }

  return {
    MAX_RATE_PERCENT, MAX_INSTALLMENTS, RATE_SCALE, ROUNDING_RULES, ADJUSTMENTS, DEFAULT_TEMPLATE_ID, ROW_START, ROW_END,
    CalcError, calculate, validate, monthlyPaymentFormula, installmentsFormula,
    parseInteger, parseRate, formatRate, normalizeNumberText,
    addMonths, nextMonth, emptyForm, isFormReady, formToInput,
    formatYen, formatMonth, formatMonths, formatDate,
    escapeHTML, renderTemplate, removeElements, buildTemplateContext,
    defaultSettings, normalizeSettings, rateDiffersFromDefault, rateForDefault,
  };
});
