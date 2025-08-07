///
///  # PhotoCollectionViewItem.swift
///
/// - Author: Created by Geoff G. on 08/01/2025
///
/// - Description:
///
///    - Subclass to represent a photo item in the collection view
///

import Cocoa

class PhotoCollectionViewItem: NSCollectionViewItem {

    
    @IBOutlet weak var imageViewPhoto: NSImageView!
    
    var rightClickGesture : NSClickGestureRecognizer?

    public var vcParent : ViewController?
    
    override func viewDidLoad() {
        
        super.viewDidLoad()

        self.imageViewPhoto.imageScaling = .scaleProportionallyUpOrDown
        
        self.rightClickGesture = NSClickGestureRecognizer(target: self,
                                action: #selector(rightClickGestureHandler(_:)))
        self.rightClickGesture!.numberOfClicksRequired = 1
        self.rightClickGesture?.buttonMask = 0x2
        
        view.addGestureRecognizer(self.rightClickGesture!)
    
        view.wantsLayer = true
    }
    
    /// --------------------------------------------------------------------------------
    /// viewWillDisappear
    ///
    override func viewWillDisappear() {
    }
    
    /// --------------------------------------------------------------------------------
    /// isSelected
    ///
    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 3 : 0
            view.layer?.borderColor = isSelected ? AppConst.Colors.selectedColor : nil
            view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        }
    }
    
    // MARK: Mouse Context Menu
    // ---------------------------------------------------------------------------

    /// --------------------------------------------------------------------------------
    /// Right click mouse handler to display the context menu
    ///
    /// - Parameters:
    ///   - gesture: the gesture recognizer
    ///
    @objc func rightClickGestureHandler(_ gesture: NSClickGestureRecognizer) {
        
        // Do we have a parent, and is it busy?
        if ( vcParent == nil || vcParent!.isBusy! ) {
            return
        }

        let menu = NSMenu(title: "Menu")
        var menuItem : NSMenuItem?
        
        // Items
        menuItem = NSMenuItem(title: "Select Best Quality Photos",
                                   action: #selector(ViewController.selectBestQuality),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)

        menuItem = NSMenuItem(title: "Select Blurred Photos",
                             action: #selector(ViewController.selectSmudged),
                      keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)

        menuItem = NSMenuItem(title: "Select Documents & Receipts",
                                   action: #selector(ViewController.selectDocsAndReceipts),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Items
        menuItem = NSMenuItem(title: "Select All",
                                   action: #selector(ViewController.selectAllPhotos),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)
        
        menuItem = NSMenuItem(title: "Unselect All",
                                   action: #selector(ViewController.unselectAllPhotos),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)
        
        menuItem = NSMenuItem(title: "Select Inverse",
                                   action: #selector(ViewController.invertCurrentPhotoSelection),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        menuItem = NSMenuItem(title: "Open In Finder",
                                   action: #selector(ViewController.openInFinder),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menu.addItem(menuItem!)

        menuItem = NSMenuItem(title: "Open In Preview",
                              action: #selector(ViewController.openInPreview),
                                   keyEquivalent: "")
        menuItem!.target = vcParent
        menuItem!.representedObject = vcParent!.urlFolder
        menu.addItem(menuItem!)

        let location = gesture.location(in: self.view)
        menu.popUp(positioning: nil, at: location, in: self.view)
    }
}



