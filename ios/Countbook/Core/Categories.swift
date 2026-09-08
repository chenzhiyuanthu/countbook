import Foundation

/// Text labels, no icons. An icon in a category grid is a decoration that has to
/// be decoded; at a glance a word is faster, and the grid stays readable when a
/// user renames a category to something no icon exists for.
let DEFAULT_CATEGORIES: [Category] = [
    Category(id: "food", name: "餐饮", nameEn: "Food", kind: .spend, order: 0),
    Category(id: "transit", name: "交通", nameEn: "Transit", kind: .spend, order: 1),
    Category(id: "daily", name: "日用", nameEn: "Daily", kind: .spend, order: 2),
    Category(id: "clothing", name: "服饰", nameEn: "Clothing", kind: .spend, order: 3),
    Category(id: "digital", name: "数码", nameEn: "Tech", kind: .spend, order: 4),
    Category(id: "fun", name: "娱乐", nameEn: "Fun", kind: .spend, order: 5),
    Category(id: "health", name: "医疗", nameEn: "Health", kind: .spend, order: 6),
    Category(id: "social", name: "人情", nameEn: "Social", kind: .spend, order: 7),
    Category(id: "home", name: "居住", nameEn: "Home", kind: .spend, order: 8),
    Category(id: "learn", name: "学习", nameEn: "Learning", kind: .spend, order: 9),
    Category(id: "travel", name: "旅行", nameEn: "Travel", kind: .spend, order: 10),
    Category(id: "sub", name: "订阅", nameEn: "Subs", kind: .spend, order: 11),
    Category(id: "other", name: "其他", nameEn: "Other", kind: .spend, order: 12),

    Category(id: "salary", name: "工资", nameEn: "Salary", kind: .income, order: 0),
    Category(id: "bonus", name: "奖金", nameEn: "Bonus", kind: .income, order: 1),
    Category(id: "invest", name: "投资", nameEn: "Investment", kind: .income, order: 2),
    Category(id: "side", name: "兼职", nameEn: "Side work", kind: .income, order: 3),
    Category(id: "gift", name: "红包", nameEn: "Gift", kind: .income, order: 4),
    Category(id: "other-in", name: "其他", nameEn: "Other", kind: .income, order: 5),
]

let DEFAULT_SETTINGS = Settings(
    currency: "CNY",
    locale: .zhCN,
    theme: .system,
    leakCeilingFen: 3000,
    coolingFloorFen: 30000,
    reckoningWeekday: 0,
    reckoningHour: 20
)
