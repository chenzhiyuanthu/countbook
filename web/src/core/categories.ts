import type { Category } from './types'

/**
 * Text labels, no icons. An icon in a category grid is a decoration that has to
 * be decoded; at a glance a word is faster, and the grid stays readable when a
 * user renames a category to something no icon exists for.
 */
export const DEFAULT_CATEGORIES: Category[] = [
  { id: 'food', name: '餐饮', nameEn: 'Food', kind: 'spend', order: 0 },
  { id: 'transit', name: '交通', nameEn: 'Transit', kind: 'spend', order: 1 },
  { id: 'daily', name: '日用', nameEn: 'Daily', kind: 'spend', order: 2 },
  { id: 'clothing', name: '服饰', nameEn: 'Clothing', kind: 'spend', order: 3 },
  { id: 'digital', name: '数码', nameEn: 'Tech', kind: 'spend', order: 4 },
  { id: 'fun', name: '娱乐', nameEn: 'Fun', kind: 'spend', order: 5 },
  { id: 'health', name: '医疗', nameEn: 'Health', kind: 'spend', order: 6 },
  { id: 'social', name: '人情', nameEn: 'Social', kind: 'spend', order: 7 },
  { id: 'home', name: '居住', nameEn: 'Home', kind: 'spend', order: 8 },
  { id: 'learn', name: '学习', nameEn: 'Learning', kind: 'spend', order: 9 },
  { id: 'travel', name: '旅行', nameEn: 'Travel', kind: 'spend', order: 10 },
  { id: 'sub', name: '订阅', nameEn: 'Subs', kind: 'spend', order: 11 },
  { id: 'other', name: '其他', nameEn: 'Other', kind: 'spend', order: 12 },

  // 投资 — the second kind of entry is an investment result, gain or loss.
  { id: 'stock', name: '股票', nameEn: 'Stocks', kind: 'income', order: 0 },
  { id: 'fund', name: '基金', nameEn: 'Funds', kind: 'income', order: 1 },
  { id: 'wealth', name: '理财', nameEn: 'Wealth products', kind: 'income', order: 2 },
  { id: 'other-in', name: '其他', nameEn: 'Other', kind: 'income', order: 3 },
  // The earlier income set is kept only so a row filed under it keeps its label.
  { id: 'salary', name: '工资', nameEn: 'Salary', kind: 'income', order: 10, archived: true },
  { id: 'bonus', name: '奖金', nameEn: 'Bonus', kind: 'income', order: 11, archived: true },
  { id: 'invest', name: '投资', nameEn: 'Investment', kind: 'income', order: 12, archived: true },
  { id: 'side', name: '兼职', nameEn: 'Side work', kind: 'income', order: 13, archived: true },
  { id: 'gift', name: '红包', nameEn: 'Gift', kind: 'income', order: 14, archived: true },
]

export const DEFAULT_SETTINGS = {
  currency: 'CNY',
  locale: 'zh-CN' as const,
  theme: 'system' as const,
  leakCeilingFen: 3000,
  coolingFloorFen: 30000,
  reckoningWeekday: 0,
  reckoningHour: 20,
}
