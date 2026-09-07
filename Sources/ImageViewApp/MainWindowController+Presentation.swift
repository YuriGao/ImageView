import AppKit
import ImageViewCore
import SwiftUI

extension MainWindowController {
    func syncFilmstripContent(navigationState: NavigationState?) {
        guard settings.showsFilmstrip else {
            filmstripView.apply(items: [], current: nil)
            return
        }
        filmstripView.apply(
            items: navigationState?.items ?? [],
            current: navigationState?.currentItem
        )
    }

    func updateContinuousReadingPresentation() {
        let shouldShow = settings.usesContinuousReading
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        continuousReadingView.isHidden = !shouldShow
        canvas.isHidden = shouldShow || isFolderBrowserMode
        if shouldShow {
            refreshContinuousReadingWindow()
        } else {
            continuousReadingTask?.cancel()
            continuousReadingTask = nil
        }
        bottomZoomLabel.isHidden = shouldShow || isFolderBrowserMode || viewModel.currentImage == nil
    }

    func refreshContinuousReadingWindow() {
        continuousReadingTask?.cancel()
        let viewModel = viewModel
        let focusedItemID = continuousReadingFocusID ?? viewModel.navigationState?.currentItem?.id
        continuousReadingTask = Task { [weak self, viewModel] in
            let pages = await viewModel.continuousReadingPages(centeredAt: focusedItemID)
            guard !Task.isCancelled, let self, self.settings.usesContinuousReading else { return }
            self.continuousReadingView.apply(
                pages: pages,
                currentItemID: focusedItemID
            )
        }
    }

    func updateInspector(metadata: ImageMetadata?) {
        inspectorView.rootView = InspectorView(
            metadata: metadata,
            isDocked: isInspectorDocked,
            onToggleDock: { [weak self] in self?.toggleInspectorDock() },
            onClose: { [weak self] in self?.settings.showsInspector = false }
        )
    }

    func toggleInspectorDock() {
        isInspectorDocked.toggle()
        updateInspector(metadata: viewModel.currentMetadata)
        updateInspectorLayout()
    }

    func updateInspectorLayout() {
        let shouldReserveSidebar = isInspectorDocked
            && settings.showsInspector
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        canvasTrailingConstraint?.constant = shouldReserveSidebar ? -252 : 0
        inspectorView.layer?.cornerRadius = shouldReserveSidebar ? 0 : 8
        rootView.layoutSubtreeIfNeeded()
    }

    func revealFilmstripOverlay() {
        guard filmstripIsEligible(pointerIsActive: true) else {
            hideFilmstripOverlay(immediately: true)
            return
        }
        cancelFilmstripAutoHide()
        filmstripOverlayView.isHidden = false

        if filmstripOverlayView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                filmstripOverlayView.animator().alphaValue = 1
            }
        }

        scheduleFilmstripAutoHide()
    }

    func cancelFilmstripAutoHide() {
        filmstripAutoHide.cancel()
    }

    func filmstripIsEligible(pointerIsActive: Bool) -> Bool {
        Self.shouldDisplayFilmstripOverlay(
            isEnabled: settings.showsFilmstrip,
            hasLoadedImage: viewModel.currentImage != nil,
            canvasScale: canvas.scale,
            pointerIsActive: pointerIsActive
        )
    }

    func scheduleFilmstripAutoHide() {
        guard Self.shouldAutoHideFilmstrip(
            isEnabled: settings.showsFilmstrip,
            pointerIsOverOverlay: isPointerOverFilmstrip
        ) else { return }
        filmstripAutoHide.schedule(after: Self.overlayAutoHideDelay) { [weak self] in
            self?.hideFilmstripOverlay()
        }
    }

    func hideFilmstripOverlay(immediately: Bool = false) {
        cancelFilmstripAutoHide()
        guard !filmstripOverlayView.isHidden else { return }

        if immediately {
            isPointerOverFilmstrip = false
            filmstripOverlayView.alphaValue = 0
            filmstripOverlayView.isHidden = true
            return
        }

        let generation = filmstripAutoHide.generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            filmstripOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.filmstripAutoHide.generation == generation else { return }
                self.filmstripOverlayView.isHidden = true
            }
        }
    }

    func revealPageControls() {
        guard Self.shouldDisplayPageControls(
            itemCount: viewModel.navigationState?.items.count ?? 0,
            isCropping: cropOverlay.isCropping
        ) else {
            hidePageControls(immediately: true)
            return
        }

        cancelPageControlsAutoHide()
        pageNavigationOverlayView.isHidden = false
        if pageNavigationOverlayView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                pageNavigationOverlayView.animator().alphaValue = 1
            }
        }
        schedulePageControlsAutoHide()
    }

    func cancelPageControlsAutoHide() {
        pageControlsAutoHide.cancel()
    }

    func schedulePageControlsAutoHide() {
        guard Self.shouldAutoHidePageControls(
            pointerIsOverControls: isPointerOverPageControls
        ) else { return }
        pageControlsAutoHide.schedule(after: Self.overlayAutoHideDelay) { [weak self] in
            self?.hidePageControls()
        }
    }

    func hidePageControls(immediately: Bool = false) {
        cancelPageControlsAutoHide()
        guard !pageNavigationOverlayView.isHidden else { return }

        if immediately {
            pageNavigationOverlayView.alphaValue = 0
            pageNavigationOverlayView.isHidden = true
            return
        }

        let generation = pageControlsAutoHide.generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            pageNavigationOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.pageControlsAutoHide.generation == generation else { return }
                self.pageNavigationOverlayView.isHidden = true
            }
        }
    }

    func showUsageHintIfNeeded() {
        guard !settings.hasShownUsageHint, usageHintView.isHidden else { return }
        settings.hasShownUsageHint = true
        usageHintView.alphaValue = 1
        usageHintView.isHidden = false
        NSAccessibility.post(element: usageHintView, notification: .announcementRequested)
        usageHintTimer?.invalidate()
        usageHintTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideUsageHint() }
        }
    }

    func hideUsageHint() {
        usageHintTimer?.invalidate()
        usageHintTimer = nil
        usageHintView.isHidden = true
    }

    func revealFullScreenChromeIfNeeded() {
        guard isInFullScreen else { return }
        setFullScreenChromeVisible(true)
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.overlayAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.setFullScreenChromeVisible(false) }
        }
    }

    func setFullScreenChromeVisible(_ visible: Bool) {
        titleBarHeightConstraint.constant = visible ? Self.titleBarHeight : 0
        bottomBarHeightConstraint.constant = visible ? Self.bottomBarHeight : 0
        titleBarView.isHidden = !visible
        titleBarDivider.isHidden = !visible
        bottomBarView.isHidden = !visible
        bottomBarDivider.isHidden = !visible
        rootView.needsLayout = true
    }

    func announceLoadedImageIfNeeded(hasImage: Bool, loadPhase: ImageLoadPhase) {
        guard hasImage, loadPhase == .full,
              let url = viewModel.navigationState?.currentItem?.url.standardizedFileURL else {
            if !hasImage { lastAnnouncedLoadedURL = nil }
            return
        }
        guard lastAnnouncedLoadedURL != url else { return }
        lastAnnouncedLoadedURL = url
        let message = String(
            format: AppStrings.text("viewer.announcement.loaded"),
            url.lastPathComponent
        )
        if let accessibilityAnnouncementHandlerForTesting {
            accessibilityAnnouncementHandlerForTesting(message)
            return
        }
        NSAccessibility.post(
            element: canvas,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

}

