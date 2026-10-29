import Testing
import MiniRules

struct PlayerSlotTests {
    @Test func leavingWhilePlayingDocks() {
        #expect(PlayerSlot.phase(afterLeavingWhilePlaying: true) == .docked)
        #expect(PlayerSlot.phase(afterLeavingWhilePlaying: false) == .idle)
    }

    @Test func selectedPlayerIsAlwaysThePage() {
        for phase in [PlayerSlot.Phase.idle, .docked] {
            for sidebar in [PlayerSlot.Sidebar.expanded, .peeking, .hidden] {
                #expect(PlayerSlot.presentation(phase: phase, isSelected: true, sidebar: sidebar) == .page)
            }
        }
    }

    @Test func idlePlayerIsACompactRow() {
        #expect(PlayerSlot.presentation(phase: .idle, isSelected: false, sidebar: .expanded) == .row)
        #expect(PlayerSlot.presentation(phase: .idle, isSelected: false, sidebar: .hidden) == .row)
    }

    @Test func dockedPlayerFollowsTheSidebar() {
        #expect(PlayerSlot.presentation(phase: .docked, isSelected: false, sidebar: .expanded) == .slot)
        #expect(PlayerSlot.presentation(phase: .docked, isSelected: false, sidebar: .peeking) == .slot)
        #expect(PlayerSlot.presentation(phase: .docked, isSelected: false, sidebar: .hidden) == .pictureInPicture)
    }

    @Test func slotIsSixteenByNine() {
        #expect(PlayerSlot.slotHeight(forWidth: 224) == 126)
        #expect(PlayerSlot.slotHeight(forWidth: 384) == 216)
    }

    @Test func recognizesYouTubeHosts() {
        #expect(PlayerSlot.isYouTube("https://www.youtube.com/watch?v=abc"))
        #expect(PlayerSlot.isYouTube("https://m.youtube.com/"))
        #expect(PlayerSlot.isYouTube("https://youtube.com/"))
        #expect(PlayerSlot.isYouTube("https://youtu.be/abc"))
        #expect(!PlayerSlot.isYouTube("https://notyoutube.com/watch?v=abc"))
        #expect(!PlayerSlot.isYouTube("https://youtube.com.example.org/"))
        #expect(!PlayerSlot.isYouTube("file:///youtube.com"))
        #expect(!PlayerSlot.isYouTube(""))
    }

    @Test func recognizesVideoLinks() {
        #expect(PlayerSlot.isYouTubeVideo("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"))
        #expect(PlayerSlot.isYouTubeVideo("https://youtu.be/dQw4w9WgXcQ"))
        #expect(PlayerSlot.isYouTubeVideo("https://www.youtube.com/shorts/abc123"))
        #expect(PlayerSlot.isYouTubeVideo("https://www.youtube.com/live/abc123"))
        #expect(!PlayerSlot.isYouTubeVideo("https://www.youtube.com/watch"))
        #expect(!PlayerSlot.isYouTubeVideo("https://www.youtube.com/watch?v="))
        #expect(!PlayerSlot.isYouTubeVideo("https://www.youtube.com/@channel"))
        #expect(!PlayerSlot.isYouTubeVideo("https://youtu.be/"))
        #expect(!PlayerSlot.isYouTubeVideo("https://example.com/watch?v=abc"))
    }
}
