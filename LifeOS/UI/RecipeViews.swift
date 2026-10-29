import SwiftUI
import LifeOSCore

// 营养页的 食谱 / 购物清单 / 备餐 三个分页。食谱由 agent 写（健康/食谱/），App 用它生成购物清单、记备餐。

/// 食谱：按早饭 / 午饭 / 加餐 / 晚饭 / 备餐分组；每个食谱选几份 → 加进购物清单；备餐的可以“做了一批”
struct RecipesPage: View {
    @Environment(AppModel.self) private var model
    /// 食谱 id → 选了几份
    @State private var picks: [String: Int] = [:]

    var body: some View {
        let recipes = model.health.recipes
        let chosen = recipes.compactMap { r in picks[r.id].flatMap { $0 > 0 ? (recipe: r, servings: $0) : nil } }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if recipes.isEmpty {
                Text("还没有食谱。跟 agent 说想做什么，它会按格式写进 健康/食谱/（每份的营养、材料和在哪买、做法）。")
                    .foregroundStyle(.secondary)
            }
            ForEach(Recipe.mealOrder + otherMeals(recipes), id: \.self) { meal in
                let group = recipes.filter { ($0.meal.isEmpty ? "其他" : $0.meal) == meal }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionTitle(text: meal, systemImage: icon(meal))
                        ForEach(group) { r in
                            RecipeCard(recipe: r, servings: Binding(get: { picks[r.id] ?? 0 }, set: { picks[r.id] = $0 }))
                        }
                    }
                }
            }
            if !chosen.isEmpty {
                HStack {
                    Text("选了 \(chosen.count) 个食谱，共 \(chosen.map(\.servings).reduce(0, +)) 份").foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") { picks = [:] }
                    Button("加到购物清单") {
                        model.addToShopping(chosen)
                        picks = [:]
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(Theme.Space.m)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private func otherMeals(_ recipes: [Recipe]) -> [String] {
        let extra = Set(recipes.map { $0.meal.isEmpty ? "其他" : $0.meal }).subtracting(Recipe.mealOrder)
        return extra.sorted()
    }

    private func icon(_ meal: String) -> String {
        switch meal {
        case "早饭": "sunrise"; case "午饭": "sun.max"; case "加餐": "takeoutbag.and.cup.and.straw"
        case "晚饭": "moon"; case "备餐": "shippingbox"; default: "fork.knife"
        }
    }
}

/// 一个食谱：名字 + 每份营养 + 选几份；点开看材料、做法、备注；备餐的可以“做了一批”
struct RecipeCard: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    @Binding var servings: Int
    @State private var open = false
    @State private var logging = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name).font(.headline)
                    Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Stepper(value: $servings, in: 0...30) {
                    Text(servings == 0 ? "买材料：—" : "买材料：\(servings) 份").monospacedDigit()
                }
                .fixedSize()
                .help("选几份，下面“加到购物清单”一起算要买多少")
            }
            DisclosureGroup("材料和做法", isExpanded: $open) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if !recipe.ingredients.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow { Text("材料"); Text("一份用量"); Text("在哪买") }.font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, i in
                                GridRow {
                                    Text(i.name)
                                    Text(i.amount).foregroundStyle(.secondary)
                                    Text(i.store).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.callout)
                    }
                    if !recipe.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { n, step in
                                Text("\(n + 1). \(step)").font(.callout)
                            }
                        }
                    }
                    if !recipe.notes.isEmpty {
                        Text(.init(recipe.notes)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            if recipe.meal == "备餐" {
                if logging {
                    PrepBatchForm(name: recipe.name, batch: recipe.batch) { logging = false }
                } else {
                    Button("做了一批…") { logging = true }.buttonStyle(.link)
                }
            }
        }
        .padding(Theme.Space.m)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var summary: String {
        guard let n = recipe.nutrition else { return "营养还没写" }
        var parts = ["每份 \(Int(n.kcal)) 千卡", "蛋白质 \(Int(n.protein)) g"]
        if let na = n.micros["sodium"] { parts.append("钠 \(Int(na)) mg") }
        if recipe.batch > 1 { parts.append("一次做 \(recipe.batch) 份") }
        return parts.joined(separator: " · ")
    }
}

/// 记一批备餐：哪天做的、冷藏几个、冷冻几个
struct PrepBatchForm: View {
    @Environment(AppModel.self) private var model
    let name: String
    let batch: Int
    let done: () -> Void
    @State private var made = Date()
    @State private var fridge = 0
    @State private var freezer = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) { fields }
                VStack(alignment: .leading, spacing: Theme.Space.s) { fields }
            }
            HStack {
                Button("记下") {
                    model.recordPrep(name: name, made: made, fridge: fridge, freezer: freezer)
                    done()
                }
                .disabled(fridge + freezer == 0)
                .buttonStyle(.borderedProminent)
                Button("取消", action: done)
                Text("冷藏按 3 天、冷冻按 2 个月算吃完期限。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // 默认：冷藏 3–4 天吃得完的放冷藏（一天一个，最多 4 个），剩下冷冻
            fridge = min(batch, 4)
            freezer = max(batch - 4, 0)
        }
    }

    @ViewBuilder private var fields: some View {
        DatePicker("做的那天", selection: $made, in: ...model.clock, displayedComponents: .date).fixedSize()
        Stepper("冷藏 \(fridge) 个", value: $fridge, in: 0...30).fixedSize()
        Stepper("冷冻 \(freezer) 个", value: $freezer, in: 0...30).fixedSize()
    }
}

/// 购物清单：按在哪买分组，点一下勾上 / 取消；清掉买好的
struct ShoppingPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.health.shopping
        let stores = items.map(\.store).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let left = items.filter { !$0.done }.count
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if items.isEmpty {
                Text("购物清单是空的。在“食谱”里选几个、各做几份，点“加到购物清单”；也可以跟 agent 说要买什么。")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("还要买 \(left) 样，已买 \(items.count - left) 样").foregroundStyle(.secondary)
                    Spacer()
                    Button("清掉买好的") { model.clearShoppingDone() }
                        .disabled(left == items.count)
                }
                ForEach(stores, id: \.self) { store in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: store, systemImage: storeIcon(store))
                        ForEach(items.filter { $0.store == store }) { item in
                            Button { model.toggleShopping(item) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.done ? Theme.green : .secondary)
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
                        }
                    }
                }
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

/// 备餐：还剩的（按吃完期限排）+ 吃了一个；吃完的收起来；记一批
struct PrepPage: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var name = ""

    var body: some View {
        let prep = model.health.prep
        let active = prep.filter { $0.left > 0 }.sorted { ($0.useBy ?? .distantFuture) < ($1.useBy ?? .distantFuture) }
        let finished = prep.filter { $0.left == 0 }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if active.isEmpty {
                Text("现在没有提前做好的饭。做了一批以后在“食谱”里点“做了一批…”，或者在下面记。").foregroundStyle(.secondary)
            } else {
                StatRow {
                    StatTile(title: "还剩", value: "\(active.map(\.left).reduce(0, +)) 个")
                    StatTile(title: "冷藏", value: "\(active.filter { !$0.place.contains("冻") }.map(\.left).reduce(0, +)) 个")
                    StatTile(title: "冷冻", value: "\(active.filter { $0.place.contains("冻") }.map(\.left).reduce(0, +)) 个")
                }
                ForEach(active) { b in PrepRow(batch: b) }
            }

            if adding {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Picker("做的什么", selection: $name) {
                        ForEach(model.health.recipes.filter { $0.meal == "备餐" }.map(\.name) + [""], id: \.self) { n in
                            Text(n.isEmpty ? "选一个" : n).tag(n)
                        }
                    }
                    .fixedSize()
                    if !name.isEmpty {
                        PrepBatchForm(name: name, batch: model.health.recipes.first { $0.name == name }?.batch ?? 4) {
                            adding = false
                            name = ""
                        }
                    } else {
                        Button("取消") { adding = false }
                    }
                }
                .padding(Theme.Space.m)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            } else {
                Button("记一批…") { adding = true }
            }

            if !finished.isEmpty {
                DisclosureGroup("吃完了的（\(finished.count) 批）") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(finished) { b in
                            Text("\(Fmt.shortDay(b.made)) 做的 \(b.name) · \(b.place) \(b.count) 个").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

/// 一批备餐：名字、放哪、还剩几个、离吃完期限几天、吃了一个
struct PrepRow: View {
    @Environment(AppModel.self) private var model
    let batch: PrepBatch
    var compact = false

    var body: some View {
        let cal = model.calendar
        let days = batch.useBy.map { cal.dateComponents([.day], from: cal.startOfDay(for: model.clock), to: $0).day ?? 0 }
        HStack(spacing: Theme.Space.m) {
            Image(systemName: batch.place.contains("冻") ? "snowflake" : "refrigerator")
                .foregroundStyle(batch.place.contains("冻") ? Theme.blue : Theme.teal).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(batch.name).fontWeight(.medium)
                Text("\(batch.place) · \(Fmt.shortDay(batch.made)) 做的 · " + useByText(days))
                    .font(.caption).foregroundStyle((days ?? 1) < 0 ? Theme.orange : .secondary)
            }
            Spacer()
            Text("还剩 \(batch.left) / \(batch.count)").monospacedDigit().foregroundStyle(.secondary)
            Button("吃了一个") { model.eatPrep(batch) }
        }
        .padding(compact ? 0 : Theme.Space.s)
    }

    private func useByText(_ days: Int?) -> String {
        guard let days else { return "没写吃完期限" }
        if days < 0 { return "过了吃完期限 \(-days) 天" }
        if days == 0 { return "今天是吃完期限" }
        return "还有 \(days) 天到吃完期限"
    }
}
