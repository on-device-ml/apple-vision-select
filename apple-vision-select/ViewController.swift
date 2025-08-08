///
///  # ViewController.swift
///
/// - Author: Created by Geoff G. on 08/01/2025
///
/// - Description:
///
///    - Allows selection of photos using new features of the Apple Vision framework, including:
///         - Select Photos with Best Aesthetics
///         - Select Smudged/Blurred Photos
///         - Select Documents & Receipts
///
/// - Seealso:
///
///    - WWDC25: Read documents using the Vision framework: https://www.youtube.com/watch?v=H-GCNsXdKzM
///    - Code Sample: https://developer.apple.com/documentation/vision/recognize-tables-within-a-document
///    - WWDC24: Discover Swift enhancements in the Vision framework https://www.youtube.com/watch?v=OkkVZJfp2MQ

import Cocoa
import Vision

// MARK: App Constants
// ---------------------------------------------------------------------------

struct AppConst {
    
    struct Strings {
        
        // App Title
        static let appTitle = "Apple Vision Select"

        static let statusDefaultMsg = "Select 􀈕 to load photos"
        static let statusPhotosLoadedMsg = "Right click on a photo for options, 􀆔-Click to select photos"
        
        static let statusPhotosSelected = "%d of %d photos selected"
        
        // Supported photo types
        static let supportedPhotos : Set = ["heic", "jpg", "jpeg", "png", "bmp", "gif", "webp"]

        static let idPhotoCollViewItem = "PhotoCollectionViewItem"
   }

    struct Thresholds {
        
        // Max supported photos to process in a folder
        static let maxPhotos : Int = -1            // -1 = no limit
        
        // Max concurrent tasks for image processing
        static let maxTasks = 5
                
        // Threshold for confirming high aesthetics photos
        static let aestheticsThreshold = Float(0.4) // Range -1 to +1

        // Threshold for confirming face capture quality
        static let faceDetectionThreshold = Float(0.1) // Range 0.0 to 1.0

        // Threshold for confirming smudged photos
        static let smudgeThreshold = Float(0.5)     // Range 0.0 to 1.0

        // Thumbnail size
        static let thumnailSize = NSMakeSize(200.0,200.0)
        
        // Maximum length of displayed paths
        static let lenDisplayedPaths = 50
    }
    
    struct Colors {
        
        static let selectedColor = NSColor.controlAccentColor.cgColor
    }
    
    struct Prefs {
        
        // Recently used folders
        static let recentFolders = "recentFolders"
   }

}

struct AppErrors {
    
    static let errDetectAestheticsFailed = "ERROR: Unable to determine aesthetics for the photo '%@'"
    static let errDetectSmudgeFailed = "ERROR: Unable to detect smudges in the photo '%@'"
    static let errReadPhotosInFolder = "ERROR: Reading photos in folder '%@'"
    static let errLaunchPreview = "ERROR: Unable to launch Preview application"
    static let errReadPhoto = "ERROR: Unable to load photo '%@' "
    static let errEnumPhotos = "ERROR: Reading enumerating photos in folder '%@'. Desc='%@'"

    static let errSecurityScopeCreateFailed = "ERROR: Unable to create security scoped folder '%@'. Desc='%@'"
    static let errSecurityScopeResolveFailed = "ERROR: Unable to resolve security scoped bookmark"
    static let errSecurityScopeAccessFailed = "ERROR: Unable to access security scoped folder '%@'"
}

// MARK: Inline Functions
// ---------------------------------------------------------------------------

@inline(__always)
func isValidString(_ str: String?) -> Bool {
    return !(str?.isEmpty ?? true)
}

@inline(__always)
func isValidFileURL(_ url: URL?) -> Bool {
    return url != nil && url!.isFileURL
}

@inline(__always)
func isValidArray<T>(_ array: [T]?) -> Bool {
    guard let array = array, !array.isEmpty else {
        return false
    }
    return array.count > 0
}

class ViewController: NSViewController,
                      NSCollectionViewDelegate,
                      NSCollectionViewDataSource,
                      NSCollectionViewDelegateFlowLayout,
                      NSMenuItemValidation {
    
    @IBOutlet weak var textCurrentFolder: NSTextField!
    @IBOutlet weak var collectionViewPhotos: NSCollectionView!
    @IBOutlet weak var textStatus: NSTextField!
    @IBOutlet weak var progress: NSProgressIndicator!
    
    @IBOutlet weak var btnSelectFolder: NSButton!
    @IBOutlet weak var btnStop: NSButton!
    @IBOutlet weak var btnRefresh: NSButton!
    
    var urlFolder : URL?
    var arrPhotos : Array<PhotoItem>?
    var isBusy : Bool?
    var shouldStop : Bool?
    var arrDeferredSecurityScopes : Array<URL> = []
    
    // MARK: User Interface
    // ---------------------------------------------------------------------------
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // Enable to reset UserDefaults
        //self.resetPrefs()
        
        isBusy = false
        shouldStop = false
        arrPhotos = []

        // CollectionView
        let identifier = NSUserInterfaceItemIdentifier(AppConst.Strings.idPhotoCollViewItem)
        let nib = NSNib(nibNamed: AppConst.Strings.idPhotoCollViewItem, bundle: nil)
        collectionViewPhotos.register(nib, forItemWithIdentifier: identifier)
        collectionViewPhotos.delegate = self
        collectionViewPhotos.dataSource = self
        collectionViewPhotos.allowsMultipleSelection = true
        collectionViewPhotos.isSelectable = true
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 1.0
        flowLayout.minimumInteritemSpacing = 1.0
        collectionViewPhotos.collectionViewLayout = flowLayout
        collectionViewPhotos.backgroundColors = [NSColor.clear]
        
        // Progress
        progress.isDisplayedWhenStopped = false
        
        // Buttons
        var imageBtn = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
        btnSelectFolder.image=imageBtn
        btnSelectFolder.toolTip = "Select a Photos Folder"
        
        imageBtn = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
        btnStop.image=imageBtn
        btnStop.toolTip = "Stop Processing Photos"
        
        imageBtn = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!
        btnRefresh.image=imageBtn
        btnRefresh.toolTip = "Refresh Photos"
        
        self.toggleControls(enabled: true, stopEnabled: false, progressStarted: false)
    }
    
    /// --------------------------------------------------------------------------------
    /// viewDidAppear
    ///
    override func viewDidAppear() {
        
        self.updateWindowTitle()

        // Do we have any recently used folders?
//        let arrRecentFolders = getRecentlyUsedFolders()
//        if ( isValidArray(arrRecentFolders) ) {
//            
//            let urlFolder = arrRecentFolders.last
//            if ( isValidFileURL(urlFolder) ) {
//                updateCurrentFolder(urlFolder: urlFolder!)
//                refreshPhotos(fromFolder: urlFolder!, reloadPhotos: true)
//                return
//            }
//        }
        self.updateStatus(msg: AppConst.Strings.statusDefaultMsg)
    }
    
    /// --------------------------------------------------------------------------------
    /// viewWillDisappear
    ///
    override func viewWillDisappear() {
        
        // Clean up any deferred security scopes
        if ( isValidArray(self.arrDeferredSecurityScopes) ) {
            for urlFolder in arrDeferredSecurityScopes {
                urlFolder.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// representedObject
    ///
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Initiates a reload of the photos from stroage and refreshes the photos CollectionView
    ///
    /// - Parameters:
    ///   - reloadPhotos: whether to reload the photos from storage
    ///
    public func refreshPhotos(fromFolder: URL, reloadPhotos: Bool) {
        
        // Should we reload our photos from storage?
        if ( reloadPhotos ) {
            Task {
                _ = await self.reloadPhotos(urlFolder: fromFolder)
                self.refreshCollection()
            }
            return
        }
        refreshCollection()
    }
    
    /// --------------------------------------------------------------------------------
    /// Refreshes the photos CollectionView
    ///
    public func refreshCollection() {
        
        DispatchQueue.main.async {
            self.collectionViewPhotos.reloadData()
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Updates the status field with a message
    ///
    /// - Parameters:
    ///   - message: the message to display
    ///
    public func updateStatus( msg: String ) {
        
        DispatchQueue.main.async {
            self.textStatus.stringValue = msg
            print(msg)
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Updates the currently selected folder
    ///
    /// - Parameters:
    ///   - urlFolder: the folder to display
    ///
    public func updateCurrentFolder( urlFolder: URL ) {
        
        self.urlFolder = urlFolder
        DispatchQueue.main.async {
            
            // Update the window title
            self.updateWindowTitle()
            
            // Update the current folder field
            self.textCurrentFolder.stringValue = self.urlFolder!.path.removingPercentEncoding!
        }
    }
        
    /// --------------------------------------------------------------------------------
    /// Displays a simple alert dialog with buttons
    ///
    /// - Parameters:
    ///   - title: the title to display
    ///   - message: he message to display
    ///   - buttons: an array of buttons to display
    ///
    public func showAlert( title: String,
                           message: String,
                           buttons: Array<String> ) -> NSApplication.ModalResponse {
        
        let alert = NSAlert()
        alert.messageText = title
        
        if ( !message.isEmpty ) {
            alert.informativeText = message
        }
        
        alert.alertStyle = .warning

        if ( !buttons.isEmpty ) {
            for (_, btnTitle) in buttons.enumerated() {
                alert.addButton(withTitle: btnTitle)
            }
        } else {
            alert.addButton(withTitle: "Ok")
        }
        
        return alert.runModal()
    }

    /// --------------------------------------------------------------------------------
    /// Displays a folder selection dialog
    ///
    /// - Parameters:
    ///   - completion: the completion block to execute when finished
    ///
    func selectFolder(completion: @escaping (URL?) -> Void) {
        
        let op = NSOpenPanel()
        op.title = "Choose a Folder"
        op.canChooseFiles = false
        op.canChooseDirectories = true
        op.allowsMultipleSelection = false
        
        op.begin { (response) in
            if response == .OK {
                completion(op.url)
            } else {
                completion(nil)
            }
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Updates the window title using the current folder & app name
    ///
    func updateWindowTitle() {
        
        var title = AppConst.Strings.appTitle
        if ( isValidFileURL(self.urlFolder) ) {
            let displayPath = self.abbreviatePath(path: self.urlFolder!.path.removingPercentEncoding!,
                                             maxLength: AppConst.Thresholds.lenDisplayedPaths)
            title = title.appendingFormat(" - %@", displayPath)
        }
        
        self.view.window!.title = title
    }
    
    /// --------------------------------------------------------------------------------
    /// Selectively enable/disable UI controls
    ///
    /// - Parameters:
    ///   - enabled: enable/disable all other controls?
    ///   - stopEnabled: enable/disable the Stop button?
    ///   - progressStarted: whether the progress indicator should be started or stopped
    ///
    private func toggleControls(enabled : Bool, stopEnabled : Bool, progressStarted: Bool) {
        
        DispatchQueue.main.async {
            
            self.btnSelectFolder.isEnabled=enabled
            self.btnRefresh.isEnabled=enabled
            self.btnStop.isEnabled=stopEnabled
            if ( progressStarted ) {
                self.progress.startAnimation(self)
            } else {
                self.progress.stopAnimation(self)
            }
        }
    }
    
    // MARK: Button Handlers
    // ---------------------------------------------------------------------------
    
    /// --------------------------------------------------------------------------------
    /// Allows selection of a new folder
    ///
    @IBAction func btnSelectFolder(_ sender: Any) {
        
        let menu = NSMenu(title: "Select Folder")
        var menuItem : NSMenuItem?

        // Do we have any recent folders?
        let arrRecentFolders = getRecentlyUsedFolders()
        for urlRecentFolder in arrRecentFolders {
            
            menuItem = NSMenuItem(title: urlRecentFolder.path.removingPercentEncoding!,
                                  action: #selector(selectRecentFolder),
                                  keyEquivalent: "")
            menuItem!.target = self
            menuItem!.representedObject = urlRecentFolder
            menu.addItem(menuItem!)
        }
        
        // Separator
        menu.addItem(NSMenuItem.separator())

        menuItem = NSMenuItem(title: "Select Other...",
                              action: #selector(selectOtherFolder),
                              keyEquivalent: "")
        menuItem!.target = self
        menu.addItem(menuItem!)
 
        // Do we have any recent folders?
        if ( arrRecentFolders.count > 0 ) {
            
            menuItem = NSMenuItem(title: "Clear Recents...",
                                  action: #selector(selectClearRecents),
                                  keyEquivalent: "")
            menuItem!.target = self
            menu.addItem(menuItem!)
        }
        
        // Display the menu
        let theEvent = NSApplication.shared.currentEvent
        let theLocation = theEvent!.locationInWindow
        menu.popUp(positioning: nil, at: theLocation, in: self.view)
    }
    
    /// --------------------------------------------------------------------------------
    /// Stops any current image processing
    ///
    @IBAction func btnStop(_ sender: Any) {
        
        self.shouldStop = true
    }
    
    /// --------------------------------------------------------------------------------
    /// Performs a full refresh of the photos in the current folder
    ///
    @IBAction func btnRefresh(_ sender: Any) {
        
        if ( !isValidFileURL(self.urlFolder) || arrPhotos!.isEmpty ) {
            return
        }
        self.refreshPhotos(fromFolder: self.urlFolder!, reloadPhotos: true)
    }
    
    // MARK: NSMenuItemValidation
    // ---------------------------------------------------------------------------
    
    /// --------------------------------------------------------------------------------
    /// Allows selection of a new folder
    ///
    /// - Parameters:
    ///   - menuItem: the title to display
    ///
    /// - Returns: whether this menu option should be enabled
    ///
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        switch menuItem.action {
            
        case #selector(unselectAllPhotos),
            #selector(openInPreview):
            return getSelectedPhotoURLs().count > 0
            
        case #selector(selectBestQuality),
             #selector(selectPhotosWithFaces),
             #selector(selectSmudged),
             #selector(selectDocsAndReceipts),
             #selector(selectAllPhotos),
             #selector(invertCurrentPhotoSelection),
             #selector(openInFinder):
            return true
            
        default:
            return true
        }
    }
    
    // MARK: Context Menu Handlers
    // ---------------------------------------------------------------------------
    
    /// --------------------------------------------------------------------------------
    /// Selects a recent folder
    ///
    @objc public func selectRecentFolder(_ sender: NSMenuItem) {

        let urlFolder = sender.representedObject as! URL
        _ = saveRecentlyUsedFolder(urlFolder: urlFolder)
        self.updateCurrentFolder(urlFolder: urlFolder)
        refreshPhotos(fromFolder: urlFolder, reloadPhotos: true)
    }

    /// --------------------------------------------------------------------------------
    /// Selects another folder
    ///
    @objc public func selectOtherFolder(_ sender: NSMenuItem) {

        selectFolder { urlFolder in
            if urlFolder == nil {
                return;
            }
            self.updateCurrentFolder(urlFolder: urlFolder!)
            self.refreshPhotos(fromFolder: urlFolder!, reloadPhotos: true)
            _ = self.saveRecentlyUsedFolder(urlFolder: urlFolder!)
        }
    }

    /// --------------------------------------------------------------------------------
    /// Clears recent folders
    ///
    @objc public func selectClearRecents(_ sender: NSMenuItem) {

        // Do they want to proceed?
        let response = showAlert(title: "Clear Recent Folders?",
                               message: "",
                               buttons: ["Yes","No"])
        if ( response != NSApplication.ModalResponse.alertFirstButtonReturn ) {
            return
        }
        
        clearRecentlyUsedFolders()
    }

    /// --------------------------------------------------------------------------------
    /// Selects all photos with the best aesthetics
    ///
    @objc public func selectBestQuality(_ sender: NSMenuItem) {

        Task {
            // Select all photos with an overallScore score > aestheticsThreshold
            await self.selectPhotosIn(urlFolder: self.urlFolder!) { pngData, photoItem in
                do {
                    let request = CalculateImageAestheticsScoresRequest()
                    let obs = try await request.perform(on: pngData)
                    photoItem.isSelected = (obs.overallScore>AppConst.Thresholds.aestheticsThreshold)
                } catch {
                    NSLog(AppErrors.errDetectAestheticsFailed,#function,photoItem.urlFile!.path)
                }
                return photoItem.isSelected!
            }
        }
    }
        
    /// --------------------------------------------------------------------------------
    /// Selects all photos with faces
    ///
    @objc public func selectPhotosWithFaces(_ sender: NSMenuItem) {

        Task {
            // Select all photos with an overallScore score > aestheticsThreshold
            await self.selectPhotosIn(urlFolder: self.urlFolder!) { pngData, photoItem in
                do {
                    let request = DetectFaceCaptureQualityRequest()
                    let arrFaceObservations = try await request.perform(on: pngData)
                    
                    // Determine if there was at least 1 observed high quality face capture
                    for faceObs in arrFaceObservations {
                        // Use this to determine actual quality of the capture
                        //if (faceObs.captureQuality!.score>AppConst.Thresholds.faceCaptureQualityThreshold) {
                        if (faceObs.confidence>AppConst.Thresholds.faceDetectionThreshold) {
                            photoItem.isSelected = true
                            break
                        }
                    }
                } catch {
                    NSLog(AppErrors.errDetectAestheticsFailed,#function,photoItem.urlFile!.path)
                }
                return photoItem.isSelected!
            }
        }
    }

    /// --------------------------------------------------------------------------------
    /// Selects all smudged/blurred photos
    ///
    @objc public func selectSmudged(_ sender: NSMenuItem) {
        
        Task {
            // Select all photos with a smudge score > smudgeThreshold
            await self.selectPhotosIn(urlFolder:self.urlFolder!) { pngData, photoItem in
                do {
                    let request = DetectLensSmudgeRequest()
                    let obs = try await request.perform(on: pngData)
                    photoItem.isSelected = (obs.confidence>AppConst.Thresholds.smudgeThreshold)
                } catch {
                    NSLog(AppErrors.errDetectSmudgeFailed,#function,photoItem.urlFile!.path)
                }
                return photoItem.isSelected!
            }
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Selects all utility photos (documents/receipts)
    ///
    @objc public func selectDocsAndReceipts(_ sender: NSMenuItem) {
        
        Task {
            // Select all photos with an overallScore of 0.0 and isUtility flagged
            await self.selectPhotosIn(urlFolder:self.urlFolder!) { pngData, photoItem in
                do {
                    let request = CalculateImageAestheticsScoresRequest()
                    let obs = try await request.perform(on: pngData)
                    photoItem.isSelected = obs.isUtility && (obs.overallScore == 0.0)
                } catch {
                    NSLog(AppErrors.errDetectSmudgeFailed,#function,photoItem.urlFile!.path)
                }
                return photoItem.isSelected!
            }
        }
    }

    /// --------------------------------------------------------------------------------
    /// Selects all photos
    ///
    @objc public func selectAllPhotos(_ sender: NSMenuItem) {
        self.toggleSelectedPhotoURLs(isSelected: true)
        self.refreshCollection()
        displayCompletionMessage(msg: String(format:AppConst.Strings.statusPhotosSelected,
                                                        getSelectedPhotoCount(),
                                                        getTotalPhotoCount()),
                            usageMsg: AppConst.Strings.statusPhotosLoadedMsg)
    }

    /// --------------------------------------------------------------------------------
    /// Unselects all photos
    ///
    @objc public func unselectAllPhotos(_ sender: NSMenuItem) {
        self.toggleSelectedPhotoURLs(isSelected: false)
        self.refreshCollection()
        displayCompletionMessage(msg: String(format:AppConst.Strings.statusPhotosSelected,
                                                        getSelectedPhotoCount(),
                                                        getTotalPhotoCount()),
                            usageMsg: AppConst.Strings.statusPhotosLoadedMsg)
    }

    /// --------------------------------------------------------------------------------
    /// Inverts the current selection
    ///
    @objc public func invertCurrentPhotoSelection(_ sender: NSMenuItem) {
        for photoItem in self.arrPhotos! {
            photoItem.isSelected! = !photoItem.isSelected!
        }
        self.refreshCollection()
        displayCompletionMessage(msg: String(format:AppConst.Strings.statusPhotosSelected,
                                                        getSelectedPhotoCount(),
                                                        getTotalPhotoCount()),
                            usageMsg: AppConst.Strings.statusPhotosLoadedMsg)
    }

    /// --------------------------------------------------------------------------------
    /// Opens the selected photos in Finder
    ///
    @objc public func openInFinder(_ sender: NSMenuItem) {
        
        // Do we have a working folder?
        if ( !isValidFileURL(self.urlFolder) ) {
            return
        }

        // Are any sample photos selected?
        let arrSelected = self.getSelectedPhotoURLs()
        if ( arrSelected.count > 0 ) {
            
            // Yes, open Finder with the selected photos
            NSWorkspace.shared.activateFileViewerSelecting(arrSelected)
        } else {
            
            // No, just open Finder
            NSWorkspace.shared.open(self.urlFolder!)
        }
    }

    /// --------------------------------------------------------------------------------
    /// Opens the selected photos in Preview
    ///
    @objc public func openInPreview(_ sender: NSMenuItem) {
        
        // Do we have a working folder?
        let urlFolder = sender.representedObject as? URL
        if ( !isValidFileURL(urlFolder) ) {
            return
        }

        // Can we start accessing this security scoped folder?
        if ( !(urlFolder!.startAccessingSecurityScopedResource()) ) {
            updateStatus(msg: String(format: AppErrors.errSecurityScopeAccessFailed, urlFolder!.path()))
            return
        }
        
        // Add to our deferred security scopes
        // Note: We don't stopAccessingSecurityScopedResources because Preview
        // runs independently. Instead, we do this when we exit the app
        //
        self.arrDeferredSecurityScopes.append(urlFolder!)
        
        var arrSelURLs : Array<URL> = []
        for photoItem in self.arrPhotos! {
            if ( photoItem.isSelected! ) {
                arrSelURLs.append(photoItem.urlFile!)
            }
        }
        
        // Did we find any selected items?
        if ( !isValidArray(arrSelURLs) ) {
            return
        }
        
        let previewBundleID = "com.apple.Preview"
        guard let previewAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: previewBundleID) else {
            print("Preview app not found")
            return
        }
        
        do {
            try NSWorkspace.shared.open(arrSelURLs,
                                        withApplicationAt: previewAppURL,
                                        options: [],
                                        configuration: [:])
        } catch {
            self.updateStatus(msg: String(format: AppErrors.errLaunchPreview))
        }
    }

    // MARK: Photo Proccessing
    // ---------------------------------------------------------------------------

    /// --------------------------------------------------------------------------------
    /// Loads/reloads information about photos from the specified folder into our array
    ///
    /// - Parameters:
    ///   - urlFolder: the path to load from
    ///
    /// - Returns: the status of the operation
    ///
    func reloadPhotos( urlFolder: URL ) async -> Bool {
        
        // Did we get a path?
        if ( !isValidFileURL(urlFolder) ) {
            return false
        }
        
        // Clear our current PhotoItems array
        self.arrPhotos?.removeAll()
        
        // Can we start accessing this security scoped folder?
        if ( !(urlFolder.startAccessingSecurityScopedResource()) ) {
            updateStatus(msg: String(format: AppErrors.errSecurityScopeAccessFailed, urlFolder.path()))
            return false
        }
        
        defer {
            urlFolder.stopAccessingSecurityScopedResource()
        }
        
        self.toggleControls(enabled: false, stopEnabled: true, progressStarted: true)
        
        var totalPhotos : Int = 0
        var countAdded : Int = 0
        self.isBusy = true

        // Limit our concurrent tasks
        let semaphore = AsyncSemaphore(value: AppConst.Thresholds.maxTasks)
        
        await withTaskGroup(of: Bool.self) { group in
            
            // Build an array suppoorted photo filenames in the folder
            var photoFiles : Array<String> = []
            do {
                // Build an array of supported image types
                let items = try FileManager.default.contentsOfDirectory(atPath: urlFolder.path)
                for item in items {
                    let fileExt = (item as NSString).pathExtension.lowercased()
                    if AppConst.Strings.supportedPhotos.contains(fileExt) {
                        photoFiles.append(item)
                    }
                }
            } catch {
                updateStatus(msg: String(format:AppErrors.errEnumPhotos,urlFolder.path,error.localizedDescription))
                return
            }
            totalPhotos = photoFiles.count
            
            // Fire off tasks to process each file concurrently
            var taskCount = 0
            for photoFile in photoFiles {
                
                group.addTask {
                    
                    // Wait for available task slot within our limit
                    await semaphore.wait()
                    
                    // Have we been asked to stop?
                    if await ( self.shouldStop! ) {
                        await semaphore.signal()
                        return false
                    }
                    
                    // Start Timer
                    let timer = await FunctionTimer()
                    await timer.start()
                    
                    let urlFile = urlFolder.appendingPathComponent(photoFile)
                    
                    // Can we create a thumbnail?
                    let thumbNail = await self.createThumbnailFor(urlImage: urlFile, size: AppConst.Thresholds.thumnailSize)
                    if ( thumbNail == nil ) {
                        return false
                    }
                    
                    _ = await MainActor.run {
                        let photoItem = PhotoItem()
                        photoItem.urlFile = urlFile
                        photoItem.thumbNail = thumbNail
                        self.arrPhotos!.append(photoItem)
                    }
                    
                    // Have we added enough photos?
                    let maxPhotos = await AppConst.Thresholds.maxPhotos
                    if maxPhotos != -1 && countAdded >= maxPhotos {
                        return false
                    }

                    // Record the time taken
                    let elapsed = await timer.stop()
                    
                    // Refresh the collection
                    await self.refreshCollection()
                    
                    // Update the status message
                    await self.updateStatus(msg: "Read photo \(countAdded) of \(totalPhotos) '\(photoFile)' in \(String(format: "%0.1fs", elapsed))...")
                    
                    // Signal completion so another task can start
                    await semaphore.signal()
                    
                    return true
                }
                taskCount += 1
            }

            // Wait for tasks to complete
            updateStatus(msg: String(format:"Waiting on %d active tasks...",taskCount))
            
            // Wait on the results as they become available
            countAdded = 0
            for await bSuccess in group {
                if ( bSuccess ) {
                    countAdded += 1
                }
            }
            
            let msg = ((countAdded == totalPhotos) ?
                        "Read \(countAdded) of \(totalPhotos) photos" :
                        "WARNING: Failed to read \(totalPhotos-countAdded) of \(totalPhotos) photos")

            self.displayCompletionMessage(msg: msg,
                                     usageMsg: AppConst.Strings.statusPhotosLoadedMsg)
        }
        
        self.isBusy = false
        self.shouldStop = false
        self.toggleControls(enabled: true, stopEnabled: false, progressStarted: false)
        
        return (countAdded == totalPhotos)
    }
    
    /// --------------------------------------------------------------------------------
    /// Creates a thumbnail image from a photo url
    ///
    /// - Parameters:
    ///    - urlImage the source image
    ///
    /// - Returns: the thumbnail image
    ///
    func createThumbnailFor(urlImage: URL, size: NSSize) -> NSImage? {
        
        // Can we load it?
        let photo = NSImage(contentsOf: urlImage)
        if ( photo == nil ) {
            return nil
        }
        
        // Can we resize the photo?
        let thumbNail = self.resizeImage(photo!, newSize:size )
        
        return thumbNail
    }
    
    /// --------------------------------------------------------------------------------
    /// Selects photos from the array using a custom photo selection block
    ///
    /// - Parameters:
    ///    - photoSelector the code block to execute to perform the photo selection
    ///
    func selectPhotosIn(urlFolder: URL, photoSelector: @escaping (Data, PhotoItem) async -> Bool) async {
        
        if ( !isValidFileURL(urlFolder) ) {
            return
        }
        self.isBusy = true
        self.shouldStop = false
        self.updateStatus(msg: "Analyzing photos...")
        self.toggleControls(enabled: false, stopEnabled: true, progressStarted: true)
        var countSel = 0

        // Can we start accessing this security scoped folder?
        if ( !(urlFolder.startAccessingSecurityScopedResource()) ) {
            updateStatus(msg: String(format: AppErrors.errSecurityScopeAccessFailed, urlFolder.path()))
            return
        }
        
        defer {
            urlFolder.stopAccessingSecurityScopedResource()
        }

        // Limit our concurrent tasks
        let semaphore = AsyncSemaphore(value: AppConst.Thresholds.maxTasks)
        
        await withTaskGroup(of: Bool.self) { group in
            
            // Fire off tasks to process the photos concurrently
            var taskCount = 0
            for photoItem in self.arrPhotos! {
                
                group.addTask {
                    
                    // Wait for available task slot within our limit
                    await semaphore.wait()
                    
                    // Have we been asked to stop?
                    if await ( self.shouldStop! ) {
                        await semaphore.signal()
                        return false
                    }

                    await self.updateStatus(msg: "Analyzing \(photoItem.urlFile!.lastPathComponent)...")
                    
                    // Can we load the image data?
                    guard let image = await NSImage.init(contentsOf: photoItem.urlFile!),
                          let tiffData = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiffData),
                          let pngData = bitmap.representation(using: .png, properties: [:]) else {
                        
                        await self.updateStatus(msg: String(format:AppErrors.errReadPhoto, photoItem.urlFile!.path()))
                        
                        return false
                    }
                    
                    // Select our photo by the specified criteria
                    let bResult = await photoSelector(pngData,photoItem)
                    countSel += (bResult ? 1 : 0)

                    // Signal completion so another task can start
                    await semaphore.signal()
                    return true
                }
                taskCount += 1
            }
            
            // Wait for tasks to complete
            updateStatus(msg: String(format:"Waiting on %d active tasks...",taskCount))
            for await _ in group {
            }
            
            let msg = (countSel > 0 ? String(format:AppConst.Strings.statusPhotosSelected,countSel,getTotalPhotoCount()) :
                                      "No photos selected")
            self.displayCompletionMessage(msg: msg,
                                     usageMsg: AppConst.Strings.statusPhotosLoadedMsg)
            
            self.refreshPhotos(fromFolder: self.urlFolder!, reloadPhotos: false)
        }
        
        self.isBusy = false
        self.shouldStop = false
        self.toggleControls(enabled: true, stopEnabled: false, progressStarted: false)
    }

    /// --------------------------------------------------------------------------------
    /// Displays a completion message, followed by a usage message
    ///
    /// - Parameters:
    ///    - completionMsg: the completion message to display
    ///    - usageMsg: the usage message to display after a delay
    ///
    func displayCompletionMessage(msg: String, usageMsg: String) {
        
        self.updateStatus(msg: msg)

        // Wait some time, then update this with a usage message
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.updateStatus(msg: usageMsg)
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Determines the URLs of all selected photos
    ///
    /// - Returns: the URLs of the currently selected photos
    ///
    func getSelectedPhotoURLs() -> Array<URL> {
        
        var arrSelected : [URL] = []
        for pi in self.arrPhotos! {
            if ( pi.isSelected! ) {
                arrSelected.append(pi.urlFile!)
            }
        }
        return arrSelected
    }
    
    /// --------------------------------------------------------------------------------
    /// Determines the total number of  photos in the current folder
    ///
    /// - Returns: the total number of  photos in the current folder
    ///
    func getTotalPhotoCount() -> Int {
        if ( self.arrPhotos == nil ) {
            return 0
        }
        return self.arrPhotos!.count
    }
    
    /// --------------------------------------------------------------------------------
    /// Determines the number of currently selected photos
    ///
    /// - Returns: the URLs of the currently selected photos
    ///
    func getSelectedPhotoCount() -> Int {
        
        var countSel = 0
        for photoItem in self.arrPhotos! {
            if ( photoItem.isSelected! ) {
                countSel += 1
            }
        }
        return countSel
    }
    
    /// --------------------------------------------------------------------------------
    /// Toggles the selection state of the photos in the array
    ///
    /// - Parameters:
    ///    - isSelected  the photos selection state
    ///
    func toggleSelectedPhotoURLs(isSelected: Bool) {
        
        for photoItem in self.arrPhotos! {
            photoItem.isSelected! = isSelected
        }
    }
  
    // MARK: UserDefaults - Recently Used Models
    // ---------------------------------------------------------------------------
    
    /// --------------------------------------------------------------------------------
    /// Resets UserDefaults app settings
    ///
    private func resetPrefs() {
            
        clearRecentlyUsedFolders()

        // Add: any other stuff to reset...
    }

    /// --------------------------------------------------------------------------------
    /// Retrieves the recently used folders from UserDefaults
    ///
    /// To support App sandboxing, the recently used folders are stored as security
    /// scoped bookmarks (Data). This method converts them back to URLs.
    ///
    /// - Returns: the array of URLs or an empty array on error
    ///
    private func getRecentlyUsedFolders() -> Array<URL> {

        // Do we have any previously saved recent folders?
        let arrRecentFolderBookmarks = UserDefaults.standard.array(forKey: AppConst.Prefs.recentFolders) as? Array<Data>
        if ( !isValidArray(arrRecentFolderBookmarks) ) {
            return []
        }
        
        // Convert the Array of Datas to URLs
        var arrRecentFolders: Array<URL> = []
        for recentFolderBookmark in arrRecentFolderBookmarks! {
            do {
                // Can we resolve this bookmark?
                var isStale = false
                let urlResolved = try URL( resolvingBookmarkData: recentFolderBookmark,
                                           options: [.withSecurityScope],
                                           relativeTo: nil,
                                           bookmarkDataIsStale: &isStale)
                if ( !isValidFileURL(urlResolved) ) {
                    continue
                }
                
                if ( !isStale ) {
                    arrRecentFolders.append(urlResolved)
                }
                
            } catch {
                updateStatus(msg: AppErrors.errSecurityScopeResolveFailed)
            }
        }
        return arrRecentFolders
    }
    
    /// --------------------------------------------------------------------------------
    /// Saves the specified last used URL to UserDefaults
    ///
    /// The URLs are ordered in the array so they appear in recently used
    /// order when displayed in a menu. To support App sandboxing, the recently
    /// used URLs are stored as security scoped bookmarks (Data)
    ///
    /// - Parameters:
    ///    - urlFolder the folder to save
    ///
    /// - Returns: the status of the operation
    ///
    private func saveRecentlyUsedFolder(urlFolder: URL) -> Bool {
        
        // Did we get the parameters we need?
        if ( !isValidFileURL(urlFolder) ) {
            return false
        }
        
        var folderBookmark : Data?
        var arrNewFolderBookmarks : Array<Data> = []

        // Do we have any existing recently used URLs in prefs?
        let arrFolderBookmarks : Array<Data>? = UserDefaults.standard.array(forKey: AppConst.Prefs.recentFolders) as? Array<Data>
        if ( isValidArray(arrFolderBookmarks) ) {
            
            // Yes, clone to a new mutable copy
            arrNewFolderBookmarks = arrFolderBookmarks!
            
            let arrFolders = getRecentlyUsedFolders()
            if ( isValidArray(arrFolders) ) {
                
                // Is our folder already in there?
                if let ind = arrFolders.firstIndex(of: urlFolder) {

                    // Yes, is it at the end of the array?
                    if ( ind == (arrNewFolderBookmarks.endIndex-1) ) {
                        
                        // Yes, outta here...
                        return true
                    }
                    
                    // No, remove it so we can append it later
                    folderBookmark = arrNewFolderBookmarks[ind]
                    arrNewFolderBookmarks.remove(at: ind)
                 }
            }
        } else {
            // No, make a new mutable array
            arrNewFolderBookmarks=Array()
        }

        // Should we create a new bookmarked URL?
        if ( folderBookmark == nil ) {
            do {
                folderBookmark = try urlFolder.bookmarkData(options:.withSecurityScope)
            } catch {
                updateStatus(msg: String(format: AppErrors.errSecurityScopeCreateFailed, self.urlFolder!.path(),error.localizedDescription))
                return false
            }
        }
        
        // Append this URL bookmark as the most recently used
        arrNewFolderBookmarks.append(folderBookmark!)
        UserDefaults.standard.set(arrNewFolderBookmarks,
                            forKey: AppConst.Prefs.recentFolders)
         
        UserDefaults.standard.synchronize()
        
        return true
    }
    
    /// --------------------------------------------------------------------------------
    /// Clears the recently used folders in UserDefaults
    ///
    private func clearRecentlyUsedFolders() {
        
        UserDefaults.standard.removeObject(forKey: AppConst.Prefs.recentFolders)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: Misc
    // ---------------------------------------------------------------------------

    /// --------------------------------------------------------------------------------
    /// Abbreviates the specified path to a specified length
    ///
    /// - Parameters:
    ///   - path: the path to the file
    ///   - maxLength: the desired maximum length
    ///
    /// - Returns:the abbreviated path
    ///
    func abbreviatePath(path: String, maxLength: Int) -> String {
        
        guard path.count > maxLength, maxLength > 5 else {
            return path
        }

        let ellipsis = "..."
        let charsToShow = maxLength - ellipsis.count
        let frontChars = Int(ceil(Double(charsToShow) / 2.0))
        let backChars = charsToShow - frontChars

        let startIndex = path.startIndex
        let endIndex = path.endIndex

        let prefix = path[startIndex..<path.index(startIndex, offsetBy: frontChars)]
        let suffix = path[path.index(endIndex, offsetBy: -backChars)..<endIndex]

        return "\(prefix)\(ellipsis)\(suffix)"
    }
    
    /// --------------------------------------------------------------------------------
    /// Resizes a specified image to a specified size
    ///
    /// - Parameters:
    ///   - image: the image to resize
    ///   - newSize: the desired size
    ///
    /// - Returns:the resized image or nil on failure
    ///
    func resizeImage(_ image: NSImage, newSize size: NSSize) -> NSImage? {
        
        guard NSBitmapImageRep(data: image.tiffRepresentation!) != nil else { return nil }

        let originalSize = image.size
        let widthRatio  = size.width / originalSize.width
        let heightRatio = size.height / originalSize.height
        let scaleFactor = min(widthRatio, heightRatio)

        let newSize = NSSize(width: originalSize.width * scaleFactor,
                             height: originalSize.height * scaleFactor)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    // MARK: NSCollectionViewDataSource
    // ---------------------------------------------------------------------------

    /// --------------------------------------------------------------------------------
    /// Returns the number of sections we want to display in our photos collection view
    ///
    /// - Parameters:
    ///   - collectionView: the collection view
    ///
    /// - Returns:the number of sections
    ///
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    /// --------------------------------------------------------------------------------
    /// Returns the current number of items we want to display in our photos collection view
    ///
    /// - Parameters:
    ///   - collectionView: the collection view
    ///   - section: the section index
    ///
    /// - Returns:the number of items in the section
    ///
    func collectionView(_ collectionView: NSCollectionView,
                    numberOfItemsInSection section: Int) -> Int {
        
        return Int(arrPhotos!.count)
    }
    
    /// --------------------------------------------------------------------------------
    /// Returns a cell for the specified photo in the photos collection view
    ///
    /// - Parameters:
    ///   - collectionView: the NSCollectionView
    ///   - indexPath: the index of the item that is about to be displayed
    ///
    /// - Returns:the cell to be displayed in the collection view
    ///
    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        let pvi = self.collectionViewPhotos.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(AppConst.Strings.idPhotoCollViewItem),
                                                      for: indexPath) as! PhotoCollectionViewItem
        
        let photoItem : PhotoItem = self.arrPhotos![indexPath.item]
        pvi.imageViewPhoto.image = photoItem.thumbNail
        pvi.vcParent = self
        pvi.isSelected = photoItem.isSelected!
        
        return pvi
    }
    
    /// --------------------------------------------------------------------------------
    /// Called when items are selected
    ///
    /// - Parameters:
    ///   - collectionView: the NSCollectionView
    ///   - indexPaths: the indices of items that were selected
    ///
    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        
        guard indexPaths.first != nil else { return }
        
        for indexPath in indexPaths {
            self.arrPhotos![indexPath.item].isSelected = true
        }
    }
    
    /// --------------------------------------------------------------------------------
    /// Called when items are deselected
    ///
    /// - Parameters:
    ///   - collectionView: the NSCollectionView
    ///   - indexPaths: the indices of items that were deselected
    ///
    func collectionView(_ collectionView: NSCollectionView,
                        didDeselectItemsAt indexPaths: Set<IndexPath>) {
        
        guard indexPaths.first != nil else { return }
        
        for indexPath in indexPaths {
            self.arrPhotos![indexPath.item].isSelected = false
        }
    }
    
    // MARK: NSCollectionViewFlowLayout
    // ---------------------------------------------------------------------------

    /// --------------------------------------------------------------------------------
    /// Returns a size for the cell based on the thumbNail
    ///
    /// - Parameters:
    ///   - collectionView: the NSCollectionView
    ///   - collectionViewLayout: the NSCollectionViewLayout
    ///   - indexPath: the index of the item that os being sized
    ///
    /// - Returns:the desired size for the cell
    ///
    func collectionView(_ collectionView: NSCollectionView,
                        layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        
        let photo = self.arrPhotos![indexPath.item].thumbNail
        return photo!.size
    }
    
}

