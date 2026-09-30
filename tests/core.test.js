// 計算・入力・テンプレート・設定のテスト。実行: npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../web/js/core.js');
const DEFAULT_TEMPLATE = require('../web/js/default-template.js');

const START = { year: 2026, month: 10 };

function input(principal, rate, mode, value, bonus = null) {
  return { principal, rate: C.parseRate(rate), mode, value, bonus, firstMonth: START };
}

/** 各行の整合性: 元本充当 = 支払額 − 利息、残高の推移、最終残高0、元本充当の合計 = 元本 */
function assertConsistent(result) {
  let balance = result.input.principal;
  result.schedule.forEach((row, i) => {
    assert.equal(row.no, i + 1);
    assert.equal(row.principal, row.payment - row.interest);
    balance -= row.principal;
    assert.equal(row.balance, balance, `row ${row.no}`);
  });
  assert.equal(result.schedule.at(-1).balance, 0);
  assert.equal(result.schedule.reduce((a, r) => a + r.principal, 0), result.input.principal);
  assert.equal(result.totalInterest, result.schedule.reduce((a, r) => a + r.interest, 0));
}

function assertCalcError(fn, code) {
  assert.throws(fn, (e) => e instanceof C.CalcError && e.code === code);
}

// --- 計算 -------------------------------------------------------------------

test('年率あり・ボーナスなし・モード②: 100万円 3% 36回', () => {
  // PMT(3%/12, 36, -1000000) = 29,081.2096… → 切り捨てで 29,081円
  const r = C.calculate(input(1_000_000, '3', 'installments', 36));
  assert.equal(r.monthlyPayment, 29_081);
  assert.equal(r.installments, 36);
  assert.equal(r.schedule[0].interest, 2_500);
  assert.deepEqual(r.schedule.slice(0, 35).map((x) => x.payment), Array(35).fill(29_081));
  // 利息を毎月切り捨てているため、最終回は月額より少し小さくなる
  assert.equal(r.lastPayment, 29_069);
  assert.equal(r.totalPayment, 29_081 * 35 + 29_069);
  assert.equal(r.totalInterest, 46_904);
  assert.deepEqual(r.schedule.at(-1).month, { year: 2029, month: 9 });
  assertConsistent(r);
});

test('年率あり・ボーナスなし・モード①: ②の月額を入れると36回に戻る', () => {
  const m2 = C.calculate(input(1_000_000, '3', 'installments', 36));
  const m1 = C.calculate(input(1_000_000, '3', 'payment', m2.monthlyPayment));
  assert.equal(m1.installments, 36);
  assert.deepEqual(m1.schedule, m2.schedule);
  assertConsistent(m1);
  // 公式では 36.00…（円未満切り捨ての分だけ36を超える）。超過分は最終回に合算する
  const n = C.installmentsFormula(1_000_000, 0.0025, 29_081);
  assert.ok(Math.abs(n - 36) < 0.001);
});

test('金利・回数・端数処理を変えても、②の月額を①に入れると同じ回数に戻る', () => {
  for (const rate of ['0', '1.5', '3', '7.8', '15', '29.9']) {
    for (const n of [1, 2, 3, 12, 24, 36, 60, 84, 120]) {
      for (const rounding of Object.keys(C.ROUNDING_RULES)) {
        const m2 = C.calculate(input(987_654, rate, 'installments', n), { rounding });
        const m1 = C.calculate(input(987_654, rate, 'payment', m2.monthlyPayment), { rounding });
        assert.equal(m1.installments, n, `rate ${rate} n ${n} ${rounding}`);
        assertConsistent(m2);
        assertConsistent(m1);
      }
    }
  }
});

test('年率0%: 月額 = 元本 ÷ 回数、利息0円', () => {
  const r = C.calculate(input(1_000_000, '0', 'installments', 36));
  assert.equal(r.monthlyPayment, 27_777);
  assert.equal(r.lastPayment, 1_000_000 - 27_777 * 35);
  assert.equal(r.totalInterest, 0);
  assert.ok(r.schedule.every((x) => x.interest === 0));
  assertConsistent(r);

  const exact = C.calculate(input(360_000, '0', 'installments', 12));
  assert.deepEqual([...new Set(exact.schedule.map((x) => x.payment))], [30_000]);

  const m1 = C.calculate(input(100_000, '0', 'payment', 30_000));
  assert.equal(m1.installments, 4);
  assert.equal(m1.lastPayment, 10_000);
});

test('端数処理（切り上げ・四捨五入）', () => {
  const up = C.calculate(input(1_000_000, '3', 'installments', 36), { rounding: 'up' });
  assert.equal(up.monthlyPayment, 29_082);
  assert.ok(up.lastPayment <= 29_082);
  assertConsistent(up);
  const nearest = C.calculate(input(1_000_000, '3', 'installments', 36), { rounding: 'nearest' });
  assert.equal(nearest.monthlyPayment, 29_081);
  assertConsistent(nearest);
});

test('差額を初回で調整', () => {
  const r = C.calculate(input(1_000_000, '0', 'installments', 36), { adjustment: 'first' });
  assert.equal(r.firstPayment, 1_000_000 - 27_777 * 35);
  assert.deepEqual(r.schedule.slice(1).map((x) => x.payment), Array(35).fill(27_777));
  assertConsistent(r);

  const withRate = C.calculate(input(1_000_000, '3', 'installments', 36), { adjustment: 'first' });
  assert.equal(withRate.installments, 36);
  assert.ok(Math.abs(withRate.lastPayment - 29_081) <= 2);
  assert.deepEqual(withRate.schedule.slice(1, 35).map((x) => x.payment), Array(34).fill(29_081));
  assertConsistent(withRate);
});

test('ボーナスあり（年2回、月を指定）: 最終回でちょうど残高0', () => {
  const bonus = { amount: 50_000, months: [6, 12] };
  const r = C.calculate(input(1_000_000, '3', 'installments', 36, bonus));
  assert.equal(r.installments, 36);
  assert.equal(r.schedule.at(-1).balance, 0);
  assert.equal(r.schedule.filter((x) => x.bonus > 0).length, 6);
  assert.equal(r.totalBonus, 300_000);
  for (const row of r.schedule.filter((x) => [6, 12].includes(x.month.month))) {
    assert.equal(row.bonus, 50_000);
    assert.equal(row.payment, r.monthlyPayment + 50_000);
  }
  assert.ok(r.monthlyPayment < 29_081);
  assert.ok(Math.abs(r.lastPayment - r.monthlyPayment) <= 36);
  assertConsistent(r);

  const m1 = C.calculate(input(1_000_000, '3', 'payment', r.monthlyPayment, bonus));
  assert.equal(m1.installments, 36);
  assertConsistent(m1);
});

test('ボーナスあり・モード①: ボーナスの分だけ回数が減る', () => {
  const bonus = { amount: 100_000, months: [7, 12] };
  const withBonus = C.calculate(input(800_000, '5', 'payment', 10_000, bonus));
  const without = C.calculate(input(800_000, '5', 'payment', 10_000));
  assert.ok(withBonus.installments < without.installments);
  assertConsistent(withBonus);
  assertConsistent(without);
});

test('月額が利息を下回っても、ボーナスで元本が減るなら完済できる', () => {
  const bonus = { amount: 100_000, months: [6, 12] };
  assertConsistent(C.calculate(input(1_000_000, '12', 'payment', 5_000, bonus)));
});

test('完済不能な条件でエラー', () => {
  assertCalcError(() => C.calculate(input(1_000_000, '3', 'payment', 2_500)), 'cannotRepay');
  assertCalcError(() => C.calculate(input(1_000_000, '3', 'payment', 1_000)), 'cannotRepay');
  assertCalcError(() => C.calculate(input(1_000_000, '12', 'payment', 5_000, { amount: 1_000, months: [6] })), 'cannotRepay');
  assertCalcError(() => C.calculate(input(10_000_000, '0', 'payment', 1_000)), 'tooManyInstallments');
});

test('入力チェック', () => {
  const cases = [
    [input(0, '3', 'installments', 12), 'invalidPrincipal'],
    [input(-1, '3', 'installments', 12), 'invalidPrincipal'],
    [input(100_000, '-0.1', 'installments', 12), 'invalidRate'],
    [input(100_000, '30.01', 'installments', 12), 'invalidRate'],
    [input(100_000, '3', 'installments', 0), 'invalidInstallments'],
    [input(100_000, '3', 'installments', 601), 'tooManyInstallments'],
    [input(100_000, '3', 'payment', 0), 'invalidMonthlyPayment'],
    [input(100_000, '3', 'installments', 12, { amount: 1, months: [13] }), 'invalidBonusMonth'],
    [input(100_000, '3', 'installments', 12, { amount: 200_000, months: [6, 12] }), 'bonusTooLarge'],
  ];
  for (const [value, code] of cases) assertCalcError(() => C.calculate(value), code);
});

test('公式', () => {
  assert.ok(Math.abs(C.monthlyPaymentFormula(1_000_000, 0.0025, 36) - 29_081.2096) < 0.001);
  assert.equal(C.monthlyPaymentFormula(1_200, 0, 12), 100);
  assert.equal(C.installmentsFormula(1_000_000, 0.0025, 2_500), null);
});

test('年月', () => {
  assert.deepEqual(C.addMonths({ year: 2026, month: 11 }, 2), { year: 2027, month: 1 });
  assert.deepEqual(C.addMonths({ year: 2026, month: 1 }, 11), { year: 2026, month: 12 });
  assert.deepEqual(C.addMonths({ year: 2026, month: 12 }, 24), { year: 2028, month: 12 });
  assert.deepEqual(C.nextMonth(new Date(2026, 11, 15)), { year: 2027, month: 1 });
});

// --- 入力の解釈・書式 ------------------------------------------------------

test('入力フォームの解釈（全角・カンマ・単位つき）', () => {
  const form = C.emptyForm([6, 12], new Date(2026, 8, 30));
  assert.deepEqual(form.firstMonth, { year: 2026, month: 10 });
  Object.assign(form, { principalText: '１,０００,０００円', rateText: '３．０%', installmentsText: '36' });
  const inp = C.formToInput(form);
  assert.equal(inp.principal, 1_000_000);
  assert.equal(inp.rate, 30000n);
  assert.equal(inp.mode, 'installments');
  assert.equal(inp.value, 36);
  assert.equal(inp.bonus, null);

  form.installmentsText = '3.5';
  assertCalcError(() => C.formToInput(form), 'invalidInstallments');
  form.installmentsText = '36';
  form.rateText = 'abc';
  assertCalcError(() => C.formToInput(form), 'invalidRate');
  form.rateText = '3.12345';
  assertCalcError(() => C.formToInput(form), 'invalidRate');
  form.rateText = '3';
  form.bonusEnabled = true;
  form.bonusAmountText = '50,000';
  assert.deepEqual(C.formToInput(form).bonus, { amount: 50_000, months: [6, 12] });

  form.mode = 'payment';
  assert.equal(C.isFormReady(form), false);
  form.paymentText = '29081';
  assert.equal(C.formToInput(form).value, 29_081);
});

test('年率の文字列', () => {
  assert.equal(C.parseRate('3'), 30000n);
  assert.equal(C.parseRate('2.5'), 25000n);
  assert.equal(C.parseRate('.5'), 5000n);
  assert.equal(C.parseRate('0.0001'), 1n);
  assert.equal(C.parseRate(''), null);
  assert.equal(C.parseRate('.'), null);
  assert.equal(C.parseRate('1.2.3'), null);
  assert.equal(C.formatRate(30000n), '3');
  assert.equal(C.formatRate(25000n), '2.5');
  assert.equal(C.formatRate(1n), '0.0001');
});

test('表示の書式', () => {
  assert.equal(C.formatYen(0), '0');
  assert.equal(C.formatYen(999), '999');
  assert.equal(C.formatYen(1_000), '1,000');
  assert.equal(C.formatYen(1_234_567), '1,234,567');
  assert.equal(C.formatYen(-46_904), '-46,904');
  assert.equal(C.formatMonths([12, 6]), '6月・12月');
  assert.equal(C.formatDate(new Date(2026, 8, 30)), '2026年9月30日');
});

// --- 年率の既定値 -----------------------------------------------------------

test('年率の既定値: 別の値を入力しても変わらず、「既定にする」のときだけ保存・再起動後も保持', () => {
  // 設定の保存・読み込み（localStorage の代わり）
  const storage = new Map();
  const save = (s) => storage.set('settings', JSON.stringify(s));
  const load = () => C.normalizeSettings(JSON.parse(storage.get('settings') ?? 'null'));

  // 1回目の起動: 既定値 3.0% を保存
  let settings = load();
  settings.defaultRate = C.rateForDefault('3.0');
  save(settings);

  // 2回目の起動: 既定値が入力欄に入る
  settings = load();
  let rateText = settings.defaultRate;
  assert.equal(rateText, '3');
  assert.equal(C.rateDiffersFromDefault(rateText, settings.defaultRate), false);

  // 一時的に別の年率を入力しても、既定値は変わらない
  rateText = '4.5';
  assert.equal(C.rateDiffersFromDefault(rateText, settings.defaultRate), true);
  assert.equal(load().defaultRate, '3');

  // 「この値を既定にする」を押したときだけ更新される
  settings.defaultRate = C.rateForDefault(rateText);
  save(settings);
  assert.equal(C.rateDiffersFromDefault(rateText, settings.defaultRate), false);

  // 3回目の起動
  assert.equal(load().defaultRate, '4.5');
});

test('年率の既定値: 不正な値は既定にできない', () => {
  assert.equal(C.rateForDefault('abc'), null);
  assert.equal(C.rateForDefault('99'), null);
  assert.equal(C.rateForDefault('-1'), null);
  assert.equal(C.rateDiffersFromDefault('', '3'), true);
  assert.equal(C.rateDiffersFromDefault('3.00', '3'), false);
});

// --- 設定 -------------------------------------------------------------------

test('設定: 欠けた項目・不正な値は既定値で補う', () => {
  assert.deepEqual(C.normalizeSettings(null), C.defaultSettings());
  const s = C.normalizeSettings({ clinicName: '古い設定', defaultRate: '2.5', themeColor: 'red', rounding: 'x', templateId: 'missing' });
  assert.equal(s.clinicName, '古い設定');
  assert.equal(s.defaultRate, '2.5');
  assert.equal(s.themeColor, C.defaultSettings().themeColor);
  assert.equal(s.rounding, 'down');
  assert.equal(s.templateId, 'default');
});

test('設定: 書き出し → 別の端末で読み込みで同じ内容になる', () => {
  const s = C.defaultSettings();
  Object.assign(s, {
    clinicName: 'さくら歯科', logo: 'data:image/png;base64,AAAA', themeColor: '#112233', rounding: 'nearest',
    adjustment: 'first', defaultRate: '6.8', templates: [{ id: 't1', name: 'simple.html', html: '<p>x</p>' }], templateId: 't1',
  });
  assert.deepEqual(C.normalizeSettings(JSON.parse(JSON.stringify(s))), s);
});

test('設定に患者に関する項目を含まない', () => {
  const json = JSON.stringify(C.defaultSettings());
  for (const key of ['patient', 'principal', 'installments']) assert.ok(!json.includes(key), key);
});

// --- テンプレート -----------------------------------------------------------

const TEMPLATE = `<h1>{{clinic_name}}</h1><p>{{ patient_name }}様</p>
<p data-show="interest">利息 {{total_interest}}円</p>
<table>
<!-- ROW_START -->
<tr>
  <td>{{row.no}}</td>
  <td>{{row.month}}</td>
  <td>{{row.payment}}</td>
  <td data-show="interest">{{row.interest}}</td>
  <td>{{row.balance}}</td>
</tr>
<!-- ROW_END -->
</table>
<p>{{unknown}}</p>`;

function smallResult() {
  return C.calculate({ principal: 120_000, rate: C.parseRate('6'), mode: 'installments', value: 3, bonus: null, firstMonth: { year: 2026, month: 11 } });
}

test('テンプレート: 行の複製・値のエスケープ', () => {
  const result = smallResult();
  const settings = { ...C.defaultSettings(), clinicName: 'A&B <歯科>' };
  const html = C.renderTemplate(TEMPLATE, C.buildTemplateContext(result, settings, '山田 太郎', true));
  assert.ok(html.includes('<h1>A&amp;B &lt;歯科&gt;</h1>'));
  assert.ok(html.includes('<p>山田 太郎様</p>'));
  assert.equal(html.split('<tr>').length - 1, 3);
  assert.ok(html.includes('<td>2026年11月</td>'));
  assert.ok(html.includes('<td>2027年1月</td>'));
  assert.ok(html.includes('>600</td>'));
  assert.ok(html.includes(`利息 ${C.formatYen(result.totalInterest)}円`));
  assert.ok(!html.includes('ROW_START'));
  assert.ok(html.includes('{{unknown}}'));
});

test('テンプレート: 利息を表示しないとき data-show="interest" を除去', () => {
  const ctx = C.buildTemplateContext(smallResult(), C.defaultSettings(), '', false);
  const html = C.renderTemplate(TEMPLATE, ctx);
  assert.ok(!html.includes('data-show="interest"'));
  assert.ok(!html.includes('利息'));
  assert.ok(!html.includes('>600<'));
  assert.equal(html.split('<td>').length - 1, 12);
  assert.equal(ctx.values.total_interest, '');
});

test('テンプレート: 入れ子の要素・void要素・自己終了タグの除去', () => {
  const html = `<div>A<div data-show='interest'>B<div>C</div>D<br><img src="x"/></div>E</div><img data-show="interest" src="y">F<span data-show="interest"/>G`;
  assert.equal(C.removeElements(html, 'interest'), '<div>AE</div>FG');
});

test('テンプレート: ボーナスが無いとき data-show="bonus" を除去', () => {
  const tpl = '<tr data-show="bonus"><td>{{bonus_amount}}</td></tr>ok';
  assert.equal(C.renderTemplate(tpl, C.buildTemplateContext(smallResult(), C.defaultSettings(), '', false)), 'ok');
  const withBonus = C.calculate({ principal: 500_000, rate: 30000n, mode: 'installments', value: 12, bonus: { amount: 30_000, months: [6, 12] }, firstMonth: { year: 2026, month: 11 } });
  const ctx = C.buildTemplateContext(withBonus, C.defaultSettings(), '', false);
  assert.equal(C.renderTemplate(tpl, ctx), '<tr data-show="bonus"><td>30,000</td></tr>ok');
  assert.equal(ctx.values.bonus_months, '6月・12月');
});

test('同梱の既定テンプレートがすべて置換される', () => {
  const result = smallResult();
  const shown = C.renderTemplate(DEFAULT_TEMPLATE, C.buildTemplateContext(result, C.defaultSettings(), '山田', true));
  const hidden = C.renderTemplate(DEFAULT_TEMPLATE, C.buildTemplateContext(result, C.defaultSettings(), '山田', false));
  assert.ok(!shown.includes('{{'));
  assert.ok(!hidden.includes('{{'));
  assert.ok(shown.includes('うち利息'));
  assert.ok(!hidden.includes('うち利息'));
  assert.ok(!hidden.includes('data-show="interest"'));
  assert.ok(hidden.includes('山田 様'));
  assert.ok(!hidden.includes('<img'));
});
