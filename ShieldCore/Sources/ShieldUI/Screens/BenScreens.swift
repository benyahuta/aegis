// §10.3 Ben's screens: Start a family, Family tab, Add person, Device detail, Feed & release health.
// Ben sees only pass/fail/unknown per check (H5) plus his own labels from `z_admin`.

import SwiftUI
import ShieldCore

// MARK: 1. Start a family

struct StartFamilyScreen: View {
    let model: AppModel
    @State private var working = false
    @State private var failed = false

    var body: some View {
        ScreenScaffold("startFamily") {
            ScreenHeader(systemImage: "person.3.fill", title: L.t("startFamily.title"),
                         detail: AttributedString(L.t("startFamily.body")))
            Card {
                Label {
                    Secondary(L.t("startFamily.privacy"))
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(ShieldPalette.brandText.color)
                }
                .accessibilityElement(children: .combine)
            }
            if failed, let message = model.dashboardMessage {
                NoticeCard(.toDo, message)
            }
            Button {
                working = true
                Task {
                    failed = !(await model.startFamily())
                    working = false
                    // The notice appears above the button the person is still on: say it.
                    if failed, let message = model.dashboardMessage { announceForAccessibility(message) }
                }
            } label: {
                if working {
                    // Named, so VoiceOver says which action is running ("Start a family, in progress").
                    ProgressView()
                        .accessibilityLabel(L.t("startFamily.action"))
                } else {
                    Text(L.t("startFamily.action"))
                }
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .disabled(working)
            .accessibilityIdentifier("startFamily.action")
        }
        .shieldNavigationTitle(L.t("startFamily.title"))
    }
}

// MARK: 2. Family tab

struct FamilyTabScreen: View {
    let model: AppModel

    var body: some View {
        ScreenScaffold("familyTab") {
            #if os(macOS)
            // The Mac has no pull-to-refresh: a visible button (also ⌘R in the Go menu), a compact
            // one beside the heading so the family's devices start near the top of the window.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ScreenHeader(title: L.t("family.title"))
                    FamilyRefreshButton(model: model)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ScreenHeader(title: L.t("family.title"))
                    FamilyRefreshButton(model: model)
                }
            }
            #else
            ScreenHeader(title: L.t("family.title"))
            #endif
            if let message = model.dashboardMessage {
                NoticeCard(info: message)
            }
            if let dashboard = model.dashboard, !dashboard.people.isEmpty {
                ForEach(dashboard.people) { person in
                    PersonSection(model: model, person: person)
                }
            } else {
                Secondary(L.t(L.platformKey("family.empty", model.platform)))
            }
            OwnerMacSection(model: model)
            Button {
                model.familyPath.append(.addPerson)
            } label: {
                ButtonLabel(L.t("family.addPerson"), systemImage: "person.badge.plus")
            }
            .buttonStyle(.shieldPrimary)
            .accessibilityIdentifier("family.addPerson")
            Button {
                model.familyPath.append(.feedHealth)
            } label: {
                NavigationRowContent(systemImage: "waveform.path.ecg", title: L.t("family.feedHealth"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("family.feedHealth")
        }
        .shieldNavigationTitle(L.t("family.title"))
        .refreshable { await model.refreshDashboard() }
    }
}

#if os(macOS)
/// **Refresh** on Ben's Mac Family tab: fetches the latest reports (same as ⌘R).
struct FamilyRefreshButton: View {
    let model: AppModel

    var body: some View {
        Button {
            Task { await model.refreshDashboard() }
        } label: {
            if model.isRefreshingDashboard {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L.t("family.refreshing"))
            } else {
                // Icon beside the word at every size (a quiet, compact control, not a second
                // big button under the heading).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                    Text(L.t("family.refresh"))
                }
            }
        }
        .buttonStyle(.shieldQuiet)
        .disabled(model.isRefreshingDashboard)
        .accessibilityIdentifier("family.refresh")
    }
}
#endif

struct PersonSection: View {
    let model: AppModel
    let person: DashboardPerson

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowRow {
                Text(person.isSelf ? L.t("family.you") : (person.label ?? L.t("family.unnamedPerson")))
                    .shieldFont(.title2, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if person.inviteAccepted == false {
                    Text(L.t("family.invitePending"))
                        .shieldFont(.subheadline, weight: .semibold)
                        .foregroundStyle(ShieldPalette.textSecondary.color)
                }
            }
            if person.devices.isEmpty {
                Card {
                    Secondary(L.t("family.noReports"))
                }
            }
            ForEach(person.devices) { device in
                Button {
                    model.familyPath.append(.device(zoneName: person.zoneName, deviceID: device.deviceID))
                } label: {
                    DeviceRow(device: device, platform: model.platform)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family.device.\(device.deviceID.uuidString.lowercased())")
            }
        }
    }
}

enum DashboardCopy {
    static func deviceName(_ device: DashboardDevice) -> String {
        if let label = device.label { return label }
        switch device.platform {
        case .ios: return L.t("family.device.ios")
        case .mac: return L.t("family.device.mac")
        case nil: return L.t("family.device.unknown")
        }
    }

    static func lastReported(_ device: DashboardDevice) -> String {
        guard let days = device.daysSinceReport else { return L.t("family.noReports") }
        return days == 0 ? L.t("family.lastReported.today") : L.plural("family.lastReported", days)
    }

    /// The worst-status chip: grey "Not reporting" past the staleness limits (§8.4). A check that
    /// is red on the relative's device is red ("Today") here too: `DashboardCheck.tier` is
    /// computed on Ben's device from `CheckID` + status (§5.1, `DashboardTiers`).
    static func chip(_ device: DashboardDevice, catalog: CheckCatalog = .shared) -> StatusAppearance {
        guard device.staleness == .fresh else { return .cantCheck }
        let failing = device.checks.filter { $0.status == .fail && !CheckID.neverFails.contains($0.checkID) }
        if failing.contains(where: { $0.tier == .red }) { return .today }
        if !failing.isEmpty { return .toDo }
        return StatusAppearance(status: device.worstStatus, tier: .amber)
    }

    static func appearance(_ check: DashboardCheck, catalog: CheckCatalog = .shared) -> StatusAppearance {
        StatusAppearance(status: check.status, tier: check.tier)
    }

    static func title(_ id: CheckID, platform: Platform?, catalog: CheckCatalog) -> String {
        let variant = catalog.variant(id, platform: platform ?? .ios)
            ?? catalog[id]?.variants.values.first
        return variant.map { L.plain($0.titleKey) } ?? id.rawValue
    }
}

struct DeviceRow: View {
    let device: DashboardDevice
    /// The platform this copy runs on (the hint's wording), not the device's.
    var platform: Platform = .ios
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Everything the card shows, in one element (§11), including the red "written by someone
    /// else" warning: it must never be visual-only.
    static func spokenLabel(_ device: DashboardDevice) -> String {
        let chip = DashboardCopy.chip(device, catalog: .shared)
        let notReporting = device.staleness != .fresh
        return "\(DashboardCopy.deviceName(device)). \(chip.word). "
            + (notReporting ? L.t("family.notReporting") + ". " : "")
            + "\(DashboardCopy.lastReported(device))."
            + (device.creatorMismatch ? " \(L.t("deviceDetail.creatorMismatch"))." : "")
    }

    var body: some View {
        let chip = DashboardCopy.chip(device, catalog: .shared)
        let name = DashboardCopy.deviceName(device)
        let reported = DashboardCopy.lastReported(device)
        let notReporting = device.staleness != .fresh
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    // A fixed column: `laptopcomputer` is wider than `iphone`, and the names,
                    // chips and dates of a person's devices must line up.
                    Image(systemName: device.platform == .mac ? "laptopcomputer" : "iphone")
                        .shieldFont(.title2)
                        .foregroundStyle(ShieldPalette.brandText.color)
                        .frame(width: symbolColumnWidth(.title2, typeSize))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .shieldFont(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow {
                        StatusChip(chip)
                        if notReporting {
                            Text(L.t("family.notReporting"))
                                .shieldFont(.subheadline, weight: .semibold)
                                .foregroundStyle(ShieldPalette.textSecondary.color)
                        }
                    }
                    Text(reported)
                        .shieldFont(.subheadline)
                        .foregroundStyle(ShieldPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if device.creatorMismatch {
                        Label(L.t("deviceDetail.creatorMismatch"), systemImage: "person.fill.questionmark")
                            .shieldFont(.subheadline, weight: .semibold)
                            .foregroundStyle(StatusAppearance.today.accent.color)
                    }
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ShieldPalette.textSecondary.color)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(device))
        .accessibilityHint(L.t(L.platformKey("a11y.hint.deviceDetail", platform)))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: 3. Add person

struct AddPersonScreen: View {
    let model: AppModel
    @State private var label = ""
    @State private var working = false
    @State private var result: AppModel.InviteResult?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScreenScaffold("addPerson") {
            ScreenHeader(systemImage: "person.badge.plus", title: L.t("addPerson.title"),
                         detail: AttributedString(L.t("addPerson.detail")))
            Card {
                Text(L.t("addPerson.labelField"))
                    .shieldFont(.headline)
                // Vertical axis: a long name wraps onto more lines at large text sizes instead of
                // scrolling sideways out of view. The prompt uses the readable secondary color
                // (the system placeholder grey is below 4.5:1, §11).
                TextField(text: $label, prompt: Text(L.t("addPerson.labelField")).foregroundStyle(ShieldPalette.textSecondary.color),
                          axis: .vertical) {
                    Text(L.t("addPerson.labelField"))
                }
                    .lineLimit(1...4)
                    // Our own shape (the Mac's bordered style drew a box in a box): a raised fill and
                    // an edge of at least 3:1 (WCAG 1.4.11), heavier with Increase Contrast.
                    .textFieldStyle(.plain)
                    .shieldFont(.title3)
                    .padding(12)
                    .frame(minHeight: ShieldMetrics.minHitTarget + 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ShieldPalette.raised.color))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ShieldPalette.strongOutline.color, lineWidth: contrast == .increased ? 2 : 1))
                    .onChange(of: label) { _, value in
                        // One line of text: Return (which a vertical field turns into a newline) is a space.
                        let flat = value.replacingOccurrences(of: "\n", with: " ")
                        let limited = flat.count > Records.maxLabelLength ? String(flat.prefix(Records.maxLabelLength)) : flat
                        if limited != value { label = limited }
                    }
                    .accessibilityIdentifier("addPerson.label")
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                Secondary(L.t("addPerson.labelHint"))
            }
            if let result {
                Self.notice(result)
            }
            Button {
                working = true
                Task {
                    let outcome = await model.invite(label: label)
                    result = outcome
                    working = false
                    // The result appears above the button the person is still on: say it.
                    announceForAccessibility(Self.notice(outcome).spokenLabel)
                }
            } label: {
                ButtonLabel(L.t("addPerson.send"), systemImage: "message.fill")
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction(!(working || label.trimmingCharacters(in: .whitespaces).isEmpty))
            .disabled(working || label.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("addPerson.send")
        }
        .shieldNavigationTitle(L.t("addPerson.title"))
    }

    static func notice(_ result: AppModel.InviteResult) -> NoticeCard {
        switch result {
        case .shown: NoticeCard(.done, L.t("addPerson.sent"))
        case .offline: NoticeCard(info: L.t("addPerson.offline"))
        case .failed: NoticeCard(.toDo, L.t("addPerson.failed"))
        }
    }
}

// MARK: 4. Device detail

struct DeviceDetailScreen: View {
    let model: AppModel
    let zoneName: String
    let deviceID: UUID

    /// §10.3 Ben-only items (plus `os_update_stuck`, which Ben tracks here too).
    static let benOnlyIDs: Set<CheckID> = [.osUpdateStuck, .betaCatalog, .appBuildFresh, .persistenceNewItem, .chromeExtForced]

    var body: some View {
        if let device = model.device(zoneName: zoneName, deviceID: deviceID) {
            content(device)
        } else {
            ScreenScaffold("deviceDetail") {
                Secondary(L.t("deviceDetail.none"))
            }
        }
    }

    private func content(_ device: DashboardDevice) -> some View {
        let catalog = model.catalog
        let family = device.checks.filter { !Self.benOnlyIDs.contains($0.checkID) && catalog[$0.checkID]?.audience != .ben }
            .sorted { (catalog[$0.checkID]?.order ?? 0) < (catalog[$1.checkID]?.order ?? 0) }
        let benOnly = device.checks.filter { Self.benOnlyIDs.contains($0.checkID) || catalog[$0.checkID]?.audience == .ben }
        let name = DashboardCopy.deviceName(device)
        return ScreenScaffold("deviceDetail") {
            ScreenHeader(systemImage: device.platform == .mac ? "laptopcomputer" : "iphone", title: name,
                         detail: AttributedString(DashboardCopy.lastReported(device)))
            if device.staleness == .expired {
                NoticeCard(.cantCheck, L.t("deviceDetail.stale"))
            } else if device.staleness == .notReporting {
                NoticeCard(.cantCheck, L.t("family.notReporting"))
            }
            if device.creatorMismatch {
                NoticeCard(.today, L.t("deviceDetail.creatorMismatch.detail"))
            }
            ShareLink(item: textTemplate(device)) {
                ButtonLabel(L.t("deviceDetail.textThem"), systemImage: "message.fill")
            }
            .buttonStyle(.shieldPrimary)
            .accessibilityIdentifier("deviceDetail.textThem")

            SectionHeading(L.t("deviceDetail.checks"))
            if family.isEmpty {
                Secondary(L.t("deviceDetail.none"))
            } else {
                Card(padding: 6) {
                    ForEach(Array(family.enumerated()), id: \.element.checkID) { offset, check in
                        DashboardCheckRow(check: check, platform: device.platform, catalog: catalog)
                        if offset < family.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
            }
            if !benOnly.isEmpty {
                SectionHeading(L.t("deviceDetail.benOnly"))
                Card(padding: 6) {
                    ForEach(Array(benOnly.enumerated()), id: \.element.checkID) { offset, check in
                        DashboardCheckRow(check: check, platform: device.platform, catalog: catalog)
                        if offset < benOnly.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
            }
        }
        .shieldNavigationTitle(name)
    }

    /// The compiled message Ben sends himself (§10.3 "from compiled templates").
    private func textTemplate(_ device: DashboardDevice) -> String {
        if device.staleness != .fresh { return L.t("deviceDetail.text.checkIn") }
        let failing = device.checks.filter { $0.status == .fail && !Self.benOnlyIDs.contains($0.checkID) }
        // "Tap" on an iPhone, "click" on a Mac: the words are for the device it is about.
        if failing.contains(where: { $0.checkID == .osPatched }) {
            return L.t(L.platformKey("deviceDetail.text.update", device.platform ?? .ios))
        }
        return failing.isEmpty ? L.t("deviceDetail.text.allGood") : L.t("deviceDetail.text.fix")
    }
}

struct DashboardCheckRow: View {
    let check: DashboardCheck
    let platform: Platform?
    let catalog: CheckCatalog
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let appearance = DashboardCopy.appearance(check, catalog: catalog)
        let title = DashboardCopy.title(check.checkID, platform: platform, catalog: catalog)
        let selfReported = check.source == .selfReported
        let date = L.fill("deviceDetail.checkedOn", ["date": ShieldDates.day(check.checkedOn)])
        GlyphRow {
            Image(systemName: selfReported ? appearance.hollowSymbolName : appearance.symbolName)
                .shieldGlyphFont(.title3, weight: .semibold)
                .foregroundStyle(appearance.accent.color)
                // A fixed column, so every check title starts at the same place.
                .frame(width: 40, alignment: .center)
                .frame(minHeight: 32)
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .shieldFont(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 8) {
                    Text(appearance.word)
                        .shieldFont(.subheadline, weight: .bold)
                        .foregroundStyle(appearance.accent.color)
                    SourceBadge(check.source)
                }
                Text(date)
                    .shieldFont(.footnote)
                    .foregroundStyle(ShieldPalette.textSecondary.color)
                if check.writtenBySomeoneElse {
                    Label(L.t("deviceDetail.creatorMismatch"), systemImage: "person.fill.questionmark")
                        .shieldFont(.subheadline, weight: .semibold)
                        .foregroundStyle(StatusAppearance.today.accent.color)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: ShieldMetrics.minHitTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(appearance.word). \(L.badge(check.source)). \(date)."
                            + (check.writtenBySomeoneElse ? " \(L.t("deviceDetail.creatorMismatch"))." : ""))
        .accessibilityIdentifier("deviceDetail.check.\(check.checkID.rawValue)")
    }
}

// MARK: 5. Feed & release health

struct FeedHealthScreen: View {
    let model: AppModel

    var body: some View {
        let today = model.clock.today()
        let buildAge = model.build.ageDays(today: today)
        ScreenScaffold("feedHealth") {
            ScreenHeader(systemImage: "waveform.path.ecg", title: L.t("feedHealth.title"))

            SectionHeading(L.t("feedHealth.feed"))
            Card {
                InfoRow(L.t("feedHealth.feedAge"), feedAge)
                Divider()
                InfoRow(L.t("feedHealth.lastChange"), model.feedInfo?.lastSOFAChange.map(ShieldDates.day) ?? L.t("feedHealth.unknown"))
                Divider()
                InfoRow(L.t("feedHealth.source"), source)
                Divider()
                LabelValueLayout {
                    Text(L.t("feedHealth.status")).shieldFont(.body).fixedSize(horizontal: false, vertical: true)
                    StatusChip(feedAppearance)
                }
                .accessibilityElement(children: .combine)
            }

            SectionHeading(L.t(model.platform == .mac ? "feedHealth.build.mac" : "feedHealth.build"))
            Card {
                InfoRow(L.t("feedHealth.buildAge"), buildAge.map { L.plural("feedHealth.buildAge.days", $0) } ?? L.t("feedHealth.unknown"))
                if model.platform == .mac {
                    // Developer ID builds don't expire; Ben updates the Mac in person (§14.3).
                    NoticeCard(.done, L.t("feedHealth.buildAge.mac"))
                } else if let buildAge {
                    if buildAge >= BuildInfo.urgentAgeDays {
                        NoticeCard(.today, L.t("feedHealth.buildAge.day75"))
                    } else if buildAge >= BuildInfo.bannerAgeDays {
                        NoticeCard(.toDo, L.t("feedHealth.buildAge.day60"))
                    } else {
                        NoticeCard(.done, L.t("feedHealth.buildAge.ok"))
                    }
                }
            }

            SectionHeading(L.t("feedHealth.scam"))
            Card {
                InfoRow(L.t("feedHealth.scam.clear"), L.fill("feedHealth.scam.ofTotal", [
                    "count": "\(ScamCorpusStats.clearScamsDanger)", "total": "\(ScamCorpusStats.clearScamsTotal)"]))
                Divider()
                InfoRow(L.t("feedHealth.scam.benign"), L.fill("feedHealth.scam.ofTotal", [
                    "count": "\(ScamCorpusStats.benignNotDanger)", "total": "\(ScamCorpusStats.benignTotal)"]))
            }
        }
        .shieldNavigationTitle(L.t("feedHealth.title"))
    }

    private var feedAge: String {
        guard let info = model.feedInfo, info.fetchedAt != nil else { return L.t("feedHealth.feedAge.never") }
        switch info.freshness {
        case .fresh(let days), .aging(let days), .stale(let days):
            return days <= 0 ? L.t("feedHealth.feedAge.today") : L.plural("feedHealth.feedAge.days", days)
        case .never:
            return L.t("feedHealth.feedAge.never")
        }
    }

    private var source: String {
        switch model.feedInfo?.origin {
        case .network: L.t("feedHealth.source.network")
        case .cache: L.t("feedHealth.source.cache")
        case .bundledSnapshot: L.t("feedHealth.source.bundled")
        case nil: L.t("feedHealth.unknown")
        }
    }

    private var feedAppearance: StatusAppearance {
        guard let info = model.feedInfo else { return .cantCheck }
        return StatusAppearance(status: info.freshness.feedFreshStatus, tier: .amber)
    }
}
