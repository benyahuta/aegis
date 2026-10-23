// §10.1 12 About & Privacy: who made it, a live "What Ben can see" sample (exactly the synced
// check titles with ✓/✗/?), build date, last checked, sync state, "Do it all now with Ben",
// "Change my accounts list" and [Stop sharing with Ben] behind a confirm sheet.

import SwiftUI
import ShieldCore

struct AboutScreen: View {
    @Bindable var model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold("about") {
            ScreenHeader(systemImage: "info.circle.fill", title: L.t("about.title"))
            Card {
                Text(L.t("about.madeBy"))
                    .shieldFont(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                TrustLine()
            }

            if let notice = model.notice {
                NoticeCard(info: notice)
                    .accessibilityIdentifier("about.notice")
            }

            WhatBenSeesCard(model: model)

            SectionHeading(L.t("about.sync.title"))
            Card {
                let connected = model.connection == .connected
                Label {
                    Text(L.t(syncKey))
                        .shieldFont(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: connected ? "person.2.fill" : "person.2.slash")
                        .foregroundStyle(connected ? StatusAppearance.done.accent.color : StatusAppearance.cantCheck.accent.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("about.syncState")
                if model.connection == .notDelivering {
                    Secondary(L.t("about.sync.notDelivering.detail"))
                }
                Secondary(L.t("about.label"))
            }

            SectionHeading(L.t("about.details.title"))
            Card {
                InfoRow(L.t("about.version"), "\(model.build.version) (\(model.build.build))")
                Divider()
                InfoRow(L.t("about.buildDate"), model.build.buildDay.map(ShieldDates.day) ?? L.t("feedHealth.unknown"))
                Divider()
                InfoRow(L.t("about.lastChecked"), model.lastCheckedAt.map { ShieldDates.checkedLine($0, now: model.clock.now()) }
                        ?? L.t("home.notCheckedYet"))
                Divider()
                InfoRow(L.t("about.feed"), feedLine)
            }

            BackgroundChecksSection(model: model)

            Card {
                Toggle(isOn: Binding(get: { model.doItAllNow }, set: { model.setDoItAllNow($0) })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("pace.doItAllNow"))
                            .shieldFont(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Secondary(L.t("pace.doItAllNow.detail"))
                    }
                }
                .shieldToggleStyle()
                .frame(minHeight: ShieldMetrics.minHitTarget)
                .accessibilityIdentifier("about.doItAllNow")
            }

            Button {
                model.open(.accountsPicker)
            } label: {
                NavigationRowContent(systemImage: "person.crop.rectangle.stack", title: L.t("about.changeAccounts"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about.changeAccounts")

            Button {
                model.open(.whoToCall)
            } label: {
                NavigationRowContent(systemImage: "phone.circle", title: L.t("about.changeWhoToCall"))
            }
            .buttonStyle(.plain)

            Button {
                model.open(.reminders)
            } label: {
                NavigationRowContent(systemImage: "bell", title: L.t("about.reminders"),
                                     detail: L.t(model.remindersShownOn ? "about.reminders.on" : "about.reminders.off"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about.reminders")

            if !model.snapshot.optionalLinks.isEmpty {
                SectionHeading(L.t("about.optional.title"))
                ForEach(model.snapshot.optionalLinks) { item in
                    Button {
                        // The extras screen first: its "talk to Ben first" warning comes before
                        // any Settings button (turning ADP on can lock someone out for good).
                        model.open(model.route(for: item))
                    } label: {
                        NavigationRowContent(systemImage: "sparkles", title: L.plain(item.titleKey), detail: L.plain(item.whyKey))
                    }
                    .accessibilityIdentifier("about.optional.\(item.checkID.rawValue)")
                    .buttonStyle(.plain)
                }
            }

            if model.canStopSharing {
                Button {
                    model.showStopSharingConfirm = true
                } label: {
                    ButtonLabel(L.t("about.stopSharing"), systemImage: "person.crop.circle.badge.xmark")
                }
                .buttonStyle(.shieldSecondary)
                .padding(.top, 8)
                .accessibilityIdentifier("about.stopSharing")
                .confirmationDialog(L.t("about.stopSharing.confirmTitle"), isPresented: $model.showStopSharingConfirm,
                                    titleVisibility: .visible) {
                    Button(L.t("about.stopSharing.confirmAction"), role: .destructive) {
                        Task { await model.stopSharing() }
                    }
                    Button(L.t("action.cancel"), role: .cancel) {}
                } message: {
                    Text(L.t("about.stopSharing.confirmMessage"))
                }
            }
        }
        .shieldNavigationTitle(L.t("about.title"))
    }

    private var syncKey: String {
        switch model.connection {
        case .connected: model.isOwner ? "about.sync.owner" : "about.sync.connected"
        case .notDelivering: "about.sync.notDelivering"
        case .notConnected, .notJoined:
            model.sync.usesCloud || model.demo != nil ? "about.sync.notConnected" : "about.sync.local"
        }
    }

    private var feedLine: String {
        guard let info = model.feedInfo else { return L.t("feedHealth.unknown") }
        if let days = info.freshness.lastCheckedDays { return L.plural("feed.lastChecked", days) }
        return info.freshness.isUsable ? L.t("about.feed.fresh") : L.t("about.feed.unknown")
    }
}

/// The live sample of exactly what syncs (§10.1 12, H5): check titles with ✓ / ✗ / ?.
struct WhatBenSeesCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(L.t("about.whatBenSees.title"))
            Card {
                Secondary(L.t("about.whatBenSees.detail"))
                ForEach(model.snapshot.synced, id: \.checkID) { entry in
                    let title = model.catalog.variant(entry.checkID, platform: model.platform).map { L.plain($0.titleKey) }
                        ?? entry.checkID.rawValue
                    HStack(spacing: 12) {
                        Image(systemName: Self.symbol(entry.status))
                            .shieldFont(.body, weight: .bold)
                            .foregroundStyle(Self.color(entry.status))
                            .frame(minWidth: 28)
                            .accessibilityHidden(true)
                        Text(title)
                            .shieldFont(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 30)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title): \(Self.word(entry.status))")
                }
            }
            .accessibilityIdentifier("about.whatBenSees")
        }
    }

    static func symbol(_ status: Status) -> String {
        switch status {
        case .pass: "checkmark"
        case .fail: "xmark"
        case .unknown: "questionmark"
        }
    }

    static func color(_ status: Status) -> Color {
        switch status {
        case .pass: StatusAppearance.done.accent.color
        case .fail: StatusAppearance.today.accent.color
        case .unknown: StatusAppearance.cantCheck.accent.color
        }
    }

    static func word(_ status: Status) -> String {
        switch status {
        case .pass: L.t("about.whatBenSees.pass")
        case .fail: L.t("about.whatBenSees.fail")
        case .unknown: L.t("about.whatBenSees.unknown")
        }
    }
}
