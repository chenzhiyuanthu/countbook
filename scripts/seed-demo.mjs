#!/usr/bin/env node
/**
 * Generate a realistic ledger for looking at the app and for screenshots.
 * Writes the event log as JSON on stdout; nothing here ships in the product.
 *
 *   node scripts/gen-demo.mjs > demo.json
 */
const DAY = 86_400_000
// A fixed seed keeps every screenshot comparable between runs.
let seed = 20260908
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff)
const pick = (xs) => xs[Math.floor(rnd() * xs.length)]
const between = (lo, hi) => lo + Math.floor(rnd() * (hi - lo))

const TODAY = new Date(2026, 8, 8, 21, 40)
const day = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

const CATS = {
  food: { name: '餐饮', payees: ['楼下面馆', '瑞幸', '海底捞', '便利蜂', '沙县', '星巴克', '美团外卖'], lo: 1200, hi: 9800, need: 0.55 },
  transit: { name: '交通', payees: ['滴滴', '地铁', '高德打车'], lo: 300, hi: 6800, need: 0.85 },
  daily: { name: '日用', payees: ['山姆', '盒马', '京东'], lo: 2000, hi: 28000, need: 0.7 },
  clothing: { name: '服饰', payees: ['优衣库', 'Nike', '淘宝'], lo: 9900, hi: 129000, need: 0.15 },
  digital: { name: '数码', payees: ['Apple Store', '京东', '闲鱼'], lo: 19900, hi: 899000, need: 0.2 },
  fun: { name: '娱乐', payees: ['万达影城', 'Steam', 'KTV', '酒吧'], lo: 3800, hi: 68000, need: 0.05 },
  health: { name: '医疗', payees: ['同仁堂', '协和门诊'], lo: 3000, hi: 42000, need: 0.95 },
  social: { name: '人情', payees: ['婚礼份子', '同事生日'], lo: 20000, hi: 100000, need: 0.6 },
  home: { name: '居住', payees: ['房租', '物业', '电费'], lo: 15000, hi: 480000, need: 0.98 },
  learn: { name: '学习', payees: ['得到', '当当'], lo: 3900, hi: 29900, need: 0.6 },
  sub: { name: '订阅', payees: [], lo: 0, hi: 0, need: 1 },
}

const events = []
let counter = 0
const push = (wall, payload) => {
  const hlc = `${wall.toString(16).padStart(16, '0')}-${(counter++ % 65535).toString(16).padStart(4, '0')}-demo0001`
  events.push({ id: `demo-${events.length.toString(36).padStart(5, '0')}`, hlc, dev: 'demo0001', ...payload })
}

push(TODAY.getTime() - 120 * DAY, {
  t: 'standard.set',
  monthlyFen: 1_200_000,
  perCategory: { food: 250_000, transit: 60_000, daily: 150_000, clothing: 80_000, digital: 100_000, fun: 80_000, home: 380_000, social: 60_000, learn: 30_000, health: 20_000 },
})
push(TODAY.getTime() - 118 * DAY, {
  t: 'settings.patch',
  patch: { wishObject: { name: '一台 Leica Q3', priceFen: 4_290_000 }, standardAccepted: true },
})

const SUBS = [
  ['Apple One', 22_800, 'month', 22],
  ['Netflix', 9_300, 'month', 14],
  ['GitHub Copilot', 7_200, 'month', 6],
  ['健身房年卡', 298_000, 'year', 3],
  ['Notion', 5_800, 'month', 19],
]
for (const [name, amount, period, dom] of SUBS) {
  const first = new Date(2022, 0, dom)
  const next = new Date(2026, period === 'year' ? 2 : 9, dom)
  push(TODAY.getTime() - 110 * DAY, {
    t: 'sub.upsert',
    sub: {
      id: `sub-${name.replace(/\W/g, '')}`, name, amount, period, categoryId: 'sub',
      firstChargedAt: day(first), nextChargeAt: day(next),
      status: name === 'Netflix' ? 'unclaimed' : 'keep',
      usageDays: name === '健身房年卡' ? ['2026-06-02', '2026-06-19', '2026-07-04'] : [],
      detected: name === 'Netflix',
    },
  })
}
push(TODAY.getTime() - 40 * DAY, { t: 'sub.status', target: 'sub-Adobe', status: 'cancelled', day: '2026-08-01' })
push(TODAY.getTime() - 41 * DAY, {
  t: 'sub.upsert',
  sub: { id: 'sub-Adobe', name: 'Adobe CC', amount: 28_800, period: 'month', categoryId: 'sub', firstChargedAt: '2023-03-11', nextChargeAt: '2026-08-11', status: 'cancelled', cancelledAt: '2026-08-01' },
})

// Three months of entries, weighted so the current month runs over.
for (let back = 96; back >= 0; back--) {
  const d = new Date(TODAY.getTime() - back * DAY)
  const weekend = d.getDay() % 6 === 0
  const n = between(1, weekend ? 6 : 4)
  if (rnd() < 0.06) {
    push(d.getTime() + 20 * 3600_000, { t: 'day.nospend', day: day(d), on: true })
    continue
  }
  for (let i = 0; i < n; i++) {
    const catId = pick(Object.keys(CATS).filter((c) => c !== 'sub'))
    const c = CATS[catId]
    if (catId === 'home' && d.getDate() !== 5) continue
    const amount = between(c.lo, c.hi)
    const r = rnd()
    const intent = r < c.need ? 'need' : r < c.need + (1 - c.need) * 0.6 ? 'want' : 'impulse'
    const hour = intent === 'impulse' && rnd() < 0.6 ? between(22, 26) % 24 : between(8, 22)
    const at = d.getTime() + hour * 3600_000 + between(0, 59) * 60_000
    const id = `e-${back}-${i}`
    push(at, {
      t: 'entry.add',
      entry: {
        id, kind: 'spend', amount, currency: 'CNY', categoryId: catId, intent,
        note: '', merchant: pick(c.payees), day: day(d), createdAt: at,
        ...(intent === 'impulse' && amount > 40_000 && rnd() < 0.5 ? { promise: pick(['想拍点好看的', '就当犒劳自己', '别人都有']) } : {}),
      },
    })
    // Judgements exist for everything older than a week, so the report has a sample.
    if (back > 7 && intent !== 'need') {
      const worthIt = rnd() > (intent === 'impulse' ? 0.62 : 0.3)
      push(at + 3 * DAY, { t: 'review.judge', target: id, worthIt })
    }
  }
}

push(TODAY.getTime() - 25 * DAY, { t: 'entry.add', entry: { id: 'inc-1', kind: 'income', amount: 4_200_000, currency: 'CNY', categoryId: 'salary', intent: null, note: '', merchant: '公司', day: day(new Date(TODAY.getTime() - 25 * DAY)), createdAt: TODAY.getTime() - 25 * DAY } })

const WISHES = [
  ['SONY WH-1000XM6', 279_900, 12, null],
  ['人体工学椅', 489_000, 3, null],
  ['第二台显示器', 189_900, 30, 'abstained'],
  ['机械键盘', 129_900, 44, 'abstained'],
  ['露营帐篷', 89_900, 61, 'bought'],
]
WISHES.forEach(([name, price, back, outcome], i) => {
  const at = TODAY.getTime() - back * DAY
  const days = Math.min(14, Math.max(1, Math.ceil(price / 10_000)))
  push(at, { t: 'wish.add', wish: { id: `w${i}`, name, price, createdAt: at, unlockAt: at + days * DAY } })
  if (outcome) push(at + (days + 1) * DAY, { t: 'wish.resolve', target: `w${i}`, outcome })
})

process.stdout.write(JSON.stringify(events))
