
import Cocoa

class PhotoItem: NSObject {

    var urlFile : URL?
    var thumbNail : NSImage?
    var isSelected : Bool?
    
    override init() {
        urlFile = nil
        thumbNail = nil
        isSelected = false
    }
}



