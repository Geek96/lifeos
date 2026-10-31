import SwiftUI
import LifeOSCore

// 营养页的 食谱 / 购物清单 两个分页。
// 食谱只读（解析用 LifeOSCore 的 HealthStore.loadRecipes）；购物清单能勾，这是手机版唯一的写入（PhoneModel.toggleShopping）。

/// 食谱：按顿分组（早饭 / 午饭 / 加餐 / 晚饭 / 备餐，其余放最后），点进去看详情
struct PhoneRecipeSections: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let recipes = model.health.recipes
        if recipes.isEmpty {
            Section {
                Text("还没有食谱。食谱由 agent 写在 健康/食谱/ 里。").foregroundStyle(.secondary)
            }
        }
        ForEach(meals(recipes), id: \.self) { meal in
            Section {
                ForEach(recipes.filter { mealName($0) == meal }) { r in
                    NavigationLink {
                        PhoneRecipeDetail(recipe: r)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                            Text(summary(r)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label(meal, systemImage: PhoneRecipeSections.icon(meal))
            }
        }
    }

    private func mealName(_ r: Recipe) -> String { r.meal.isEmpty ? "其他" : r.meal }

    private func meals(_ recipes: [Recipe]) -> [String] {
        let present = Set(recipes.map(mealName))
        return Recipe.mealOrder.filter(present.contains) + present.subtracting(Recipe.mealOrder).sorted()
    }

    private func summary(_ r: Recipe) -> String {
        guard let n = r.nutrition else { return "营养还没写" }
        var parts = ["每份 \(Int(n.kcal)) 千卡", "蛋白 \(Int(n.protein)) g"]
        if r.batch > 1 { parts.append("一次做 \(r.batch) 份") }
        return parts.joined(separator: " · ")
    }

    static func icon(_ meal: String) -> String {
        switch meal {
        case "早饭": "sunrise"; case "午饭": "sun.max"; case "加餐": "takeoutbag.and.cup.and.straw"
        case "晚饭": "moon"; case "备餐": "shippingbox"; default: "fork.knife"
        }
    }
}

/// 一个食谱：每份营养、材料（用量和在哪买）、做法、备注
struct PhoneRecipeDetail: View {
    let recipe: Recipe

    var body: some View {
        List {
            Section("每份营养") {
                if let n = recipe.nutrition {
                    row("热量", "\(Int(n.kcal)) 千卡")
                    row("蛋白质", "\(fmt(n.protein)) g")
                    row("碳水", "\(fmt(n.carbs)) g")
                    row("脂肪", "\(fmt(n.fat)) g")
                    ForEach(Micronutrient.all.filter { n.micros[$0.key] != nil }) { m in
                        row(m.label, "\(fmt(n.micros[m.key] ?? 0)) \(m.unit)")
                    }
                } else {
                    Text("营养还没写").foregroundStyle(.secondary)
                }
                if recipe.batch > 1 {
                    row("一次做", "\(recipe.batch) 份")
                }
            }
            if !recipe.ingredients.isEmpty {
                Section("材料（一份）") {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, i in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.name)
                                if !i.amount.isEmpty {
                                    Text(i.amount).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !i.store.isEmpty {
                                Text(i.store).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !recipe.steps.isEmpty {
                Section("做法") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { n, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(n + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(step)
                        }
                    }
                }
            }
            if !recipe.notes.isEmpty {
                Section("备注") {
                    Text(.init(recipe.notes)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit() }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// 购物清单：按在哪买分组（和电脑版一样的顺序），点一下勾上 / 取消。
/// 加东西、清掉买好的都在电脑上做，这里不提供。
struct PhoneShoppingSections: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let items = model.health.shopping
        let stores = items.map(\.store).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let left = items.filter { !$0.done }.count
        Section {
            if items.isEmpty {
                Text("购物清单是空的。在电脑上的“食谱”里选几个加进来，或者跟 agent 说要买什么。")
                    .foregroundStyle(.secondary)
            } else {
                Text("还要买 \(left) 样，已买 \(items.count - left) 样").foregroundStyle(.secondary)
            }
        } footer: {
            if !items.isEmpty {
                Text("点一下勾上或取消，会同步回电脑。加东西、清掉买好的在电脑上做。")
            }
        }
        ForEach(stores, id: \.self) { store in
            Section {
                ForEach(items.filter { $0.store == store }) { item in
                    Button { model.toggleShopping(item) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? Theme.green : .secondary)
                                .imageScale(.large)
                            Text(item.text)
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.done ? [.isSelected] : [])
                    .accessibilityHint(item.done ? "取消勾选" : "勾上")
                }
            } header: {
                Label(store, systemImage: storeIcon(store))
            }
        }
    }

    private func storeIcon(_ store: String) -> String {
        switch store {
        case "超市": "cart"; case "Weee": "basket"; case "Amazon": "shippingbox"; case "IKEA": "house"
        default: "bag"
        }
    }
}

/// 底部的一句短提示（PhoneModel.notice），3 秒后消失
struct PhoneNoticeBanner: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        if let text = model.notice {
            Text(text)
                .font(.callout)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, Theme.Space.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(3))
                    if model.notice == text { model.notice = nil }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
