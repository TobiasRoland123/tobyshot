import AppKit
import Testing
@testable import TobyShot

struct AreaSuggestionSelectionTests {
    @Test func siblingHoverDoesNotBreakSteppedAncestorLock() {
        let small = CGRect(x: 10, y: 10, width: 20, height: 20)
        let parent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let sibling = CGRect(x: 40, y: 10, width: 20, height: 20)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([small, parent, sibling], pointer: CGPoint(x: 15, y: 15))

        #expect(model.rect == small)
        #expect(model.step(outward: true) == CGPoint(x: 50, y: 50))
        model.hover(at: CGPoint(x: 45, y: 15))
        #expect(model.rect == parent)
        #expect(model.step(outward: false) == CGPoint(x: 20, y: 20))
    }

    @Test func leavingLockedSelectionResetsToSmallestHoveredCandidate() {
        let small = CGRect(x: 10, y: 10, width: 20, height: 20)
        let parent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let outside = CGRect(x: 120, y: 0, width: 30, height: 30)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([small, parent, outside], pointer: CGPoint(x: 15, y: 15))
        _ = model.step(outward: true)

        model.hover(at: CGPoint(x: 125, y: 5))
        #expect(model.rect == outside)
        #expect(model.step(outward: true) == nil)
    }

    @Test func steppingStopsAtBothEndsOfContainmentPath() {
        let inner = CGRect(x: 20, y: 20, width: 20, height: 20)
        let middle = CGRect(x: 10, y: 10, width: 60, height: 60)
        let outer = CGRect(x: 0, y: 0, width: 100, height: 100)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([outer, inner, middle], pointer: CGPoint(x: 25, y: 25))

        #expect(model.rect == inner)
        #expect(model.step(outward: false) == nil)
        #expect(model.step(outward: true) == CGPoint(x: 40, y: 40))
        #expect(model.rect == middle)
        #expect(model.step(outward: true) == CGPoint(x: 50, y: 50))
        #expect(model.rect == outer)
        #expect(model.step(outward: true) == nil)
    }

    @Test func intersectingNonNestedCandidatesDoNotJoinThePath() {
        let first = CGRect(x: 0, y: 0, width: 50, height: 50)
        let crossing = CGRect(x: 25, y: 25, width: 50, height: 50)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([first, crossing], pointer: CGPoint(x: 30, y: 30))

        #expect(model.rect == first)
        #expect(model.step(outward: true) == nil)
        model.hover(at: CGPoint(x: 60, y: 60))
        #expect(model.rect == crossing)
    }

    @Test func mouseDownFreezesAbsenceWhileCandidatesArrive() {
        let model = AreaSuggestionSelection()
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        model.begin(at: CGPoint(x: 40, y: 40), bounds: bounds)
        model.replaceCandidates([CGRect(x: 20, y: 20, width: 80, height: 80)], pointer: CGPoint(x: 40, y: 40))

        #expect(model.rect == .zero)
        #expect(model.end(at: CGPoint(x: 42, y: 40)) == nil)
        #expect(model.rect == CGRect(x: 20, y: 20, width: 80, height: 80))
    }

    @Test func mouseDownFreezesSuggestionWhileCandidatesChange() throws {
        let suggestion = CGRect(x: 10, y: 10, width: 40, height: 30)
        let replacement = CGRect(x: 100, y: 100, width: 50, height: 50)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([suggestion], pointer: CGPoint(x: 20, y: 20))
        model.begin(at: CGPoint(x: 20, y: 20), bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        model.replaceCandidates([replacement], pointer: CGPoint(x: 120, y: 120))

        #expect(model.rect == suggestion)
        #expect(try #require(model.end(at: CGPoint(x: 22, y: 20))) == suggestion)
        #expect(model.rect == suggestion)
    }

    @Test func movementAtOrBelowToleranceRemainsAClick() {
        let suggestion = CGRect(x: 10, y: 10, width: 40, height: 30)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([suggestion], pointer: CGPoint(x: 20, y: 20))
        model.begin(at: CGPoint(x: 20, y: 20), bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        model.drag(to: CGPoint(x: 24, y: 20))

        #expect(!model.isDragging)
        #expect(model.rect == suggestion)
        #expect(model.end(at: CGPoint(x: 24, y: 20)) == suggestion)
    }

    @Test func lateResultsPreserveTheOriginalScrolledPath() {
        let child = CGRect(x: 10, y: 10, width: 20, height: 20)
        let parent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let sibling = CGRect(x: 40, y: 40, width: 30, height: 30)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([child, parent], pointer: CGPoint(x: 15, y: 15))
        _ = model.step(outward: true)
        model.replaceCandidates([child, parent, sibling], pointer: CGPoint(x: 50, y: 50))
        #expect(model.rect == parent)
        #expect(model.step(outward: false) == CGPoint(x: 20, y: 20))
    }

    @Test func overlappingAncestorsCannotCreateASidewaysScrollStep() {
        let child = CGRect(x: 40, y: 40, width: 20, height: 20)
        let first = CGRect(x: 0, y: 0, width: 70, height: 70)
        let crossing = CGRect(x: 30, y: 30, width: 80, height: 80)
        let outer = CGRect(x: -10, y: -10, width: 150, height: 150)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([child, first, crossing, outer], pointer: CGPoint(x: 50, y: 50))
        _ = model.step(outward: true)
        #expect(model.rect == first)
        _ = model.step(outward: true)
        #expect(model.rect == outer)
    }

    @Test func resultsArrivingDuringDragCannotReplaceItsRectangle() {
        let model = AreaSuggestionSelection()
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        model.begin(at: CGPoint(x: 40, y: 50), bounds: bounds)
        model.drag(to: CGPoint(x: 150, y: 180))
        let manual = model.rect
        model.replaceCandidates([bounds], pointer: CGPoint(x: 150, y: 180))
        model.hover(at: CGPoint(x: 200, y: 200))
        #expect(model.step(outward: true) == nil)
        #expect(model.rect == manual)
        #expect(model.end(at: CGPoint(x: 150, y: 180)) == manual)
    }

    @Test func movingBeyondToleranceStartsManualDragAtOriginalPressWithoutSnap() throws {
        let suggestion = CGRect(x: 10, y: 10, width: 80, height: 80)
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let model = AreaSuggestionSelection()
        model.replaceCandidates([suggestion], pointer: CGPoint(x: 20, y: 20))
        model.begin(at: CGPoint(x: 20, y: 20), bounds: bounds)
        model.drag(to: CGPoint(x: 26, y: 20))

        #expect(model.isDragging)
        #expect(model.rect == CGRect(x: 20, y: 20, width: 6, height: 0))
        #expect(try #require(model.end(at: CGPoint(x: 60, y: 50))) == CGRect(x: 20, y: 20, width: 40, height: 30))
    }

    @Test func manualGestureStaysManualAfterReturningNearPress() throws {
        let model = AreaSuggestionSelection()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.begin(at: CGPoint(x: 50, y: 50), bounds: bounds)
        model.drag(to: CGPoint(x: 55, y: 50))
        #expect(model.isDragging)
        model.drag(to: CGPoint(x: 51, y: 50))

        #expect(model.isDragging)
        #expect(model.end(at: CGPoint(x: 51, y: 50)) == nil)
    }

    @Test func manualCoordinatesClipAcrossDisplaysInGlobalAppKitSpace() throws {
        let left = CGRect(x: -1200, y: -200, width: 1200, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let desktop = left.union(right)
        let model = AreaSuggestionSelection()
        model.begin(at: CGPoint(x: -300, y: 100), bounds: desktop)
        model.drag(to: CGPoint(x: 500, y: 600))

        let result = try #require(model.end(at: CGPoint(x: 500, y: 600)))
        #expect(result == CGRect(x: -300, y: 100, width: 800, height: 500))
        #expect(result.intersection(left) == CGRect(x: -300, y: 100, width: 300, height: 500))
        #expect(result.intersection(right) == CGRect(x: 0, y: 100, width: 500, height: 500))
    }

    @Test func manualRectangleIsClippedAndMustMeetMinimumDimensions() throws {
        let model = AreaSuggestionSelection()
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.begin(at: CGPoint(x: 98, y: 98), bounds: bounds)
        model.drag(to: CGPoint(x: 110, y: 110))
        #expect(model.rect == CGRect(x: 98, y: 98, width: 2, height: 2))
        #expect(try #require(model.end(at: CGPoint(x: 110, y: 110))) == CGRect(x: 98, y: 98, width: 2, height: 2))

        model.begin(at: CGPoint(x: 50, y: 50), bounds: bounds)
        model.drag(to: CGPoint(x: 60, y: 51))
        #expect(model.end(at: CGPoint(x: 60, y: 51)) == nil)
    }

    @Test func redrawCallbackTracksVisibleStateChanges() {
        let model = AreaSuggestionSelection()
        var redraws = 0
        model.didChange = { redraws += 1 }
        let candidate = CGRect(x: 10, y: 10, width: 20, height: 20)
        model.replaceCandidates([candidate], pointer: CGPoint(x: 15, y: 15))
        model.begin(at: CGPoint(x: 15, y: 15), bounds: candidate)
        _ = model.end(at: CGPoint(x: 15, y: 15))

        #expect(redraws >= 2)
    }
}
