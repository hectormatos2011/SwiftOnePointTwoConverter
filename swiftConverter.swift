#!/usr/bin/env xcrun swift

import Foundation

extension String {
    func contains(find: String) -> Bool {
        return self.rangeOfString(find) != nil
    }
}

//Bash Echo Color Codes
let echoColor = "\\x1B"
let magenta = "\(echoColor)[35m"
let pink = "\(echoColor)[95m"
let red = "\(echoColor)[91m"
let green = "\(echoColor)[32m"
let brown = "\(echoColor)[33m"
let endColor = "\(echoColor)[0m"

func performCleanOnWorkspace() {
    let task = NSTask()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["xcodebuild", "-workspace", "Zazzle.xcworkspace/", "-scheme", "Zwift", "clean"]
    task.launch()
    task.waitUntilExit()
}

func initiateEchoSequence(stringToPrint: String, #verbose: Bool) {
    if verbose {
        let task = NSTask()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "-e", "echo '\(stringToPrint)'"]

        task.launch()
        task.waitUntilExit()
    }
}

class FileCrawler: SequenceType {
    let encoding : UInt
    let chunkSize : Int

    var fileHandle : NSFileHandle!
    var currentLine: NSString?
    var currentRange : NSRange = NSMakeRange(0, 0)

    let buffer : NSMutableData!
    let delimiter: NSString!
    let delimeterData : NSData!
    var atEOF : Bool = false

    init?(URL: NSURL, delimiter: String = "\n", encoding : UInt = NSUTF8StringEncoding, chunkSize : Int = 8192) {
        self.chunkSize = chunkSize
        self.encoding = encoding
        self.delimiter = delimiter

        if let fileHandle = NSFileHandle(forReadingFromURL: URL, error: nil) {
            self.fileHandle = fileHandle
        } else {
            return nil
        }
        // Create NSData object containing the line delimiter:
        if let delimData = delimiter.dataUsingEncoding(NSUTF8StringEncoding) {
            self.delimeterData = delimData
        } else {
            return nil
        }
        if let buffer = NSMutableData(capacity: chunkSize) {
            self.buffer = buffer
        } else {
            return nil
        }
    }

    deinit {
        self.close()
    }

    func generate() -> GeneratorOf<String> {
        return GeneratorOf<String> {
            if let newLine = self.nextLine() {
                if let oldLine = self.currentLine {
                    self.currentRange = NSMakeRange(self.currentRange.location + oldLine.length + self.delimiter.length, newLine.length + self.delimiter.length)
                } else {
                    self.currentRange = NSMakeRange(0, newLine.length + self.delimiter.length)
                }
                self.currentLine = newLine

                return newLine as String
            } else {
                return nil
            }
        }
    }

    /// Return next line, or nil on EOF.
    func nextLine() -> NSString? {
        if atEOF {
            return nil
        }

        // Read data chunks from file until a line delimiter is found:
        var range = buffer.rangeOfData(delimeterData, options: nil, range: NSMakeRange(0, buffer.length))
        while range.location == NSNotFound {
            var tmpData = fileHandle.readDataOfLength(chunkSize)
            if tmpData.length == 0 {
                // EOF or read error.
                atEOF = true
                if buffer.length > 0 {
                    // Buffer contains last line in file (not terminated by delimiter).
                    let line = NSString(data: buffer, encoding: encoding);
                    buffer.length = 0
                    return line
                }
                // No more lines.
                return nil
            }
            buffer.appendData(tmpData)
            range = buffer.rangeOfData(delimeterData, options: nil, range: NSMakeRange(0, buffer.length))
        }

        // Convert complete line (excluding the delimiter) to a string:
        let line = NSString(data: buffer.subdataWithRange(NSMakeRange(0, range.location)),
            encoding: encoding)

        // Remove line (and the delimiter) from the buffer:
        buffer.replaceBytesInRange(NSMakeRange(0, range.location + range.length), withBytes: nil, length: 0)

        return line
    }

    /// Start reading from the beginning of file.
    func rewind() {
        fileHandle.seekToFileOffset(0)
        buffer.length = 0
        currentRange = NSMakeRange(0, 0)
        atEOF = false
    }

    /// Close the underlying file. No reading must be done after calling this method.
    func close() {
        if fileHandle != nil {
            fileHandle.closeFile()
            fileHandle = nil
        }
    }
}

class TaskManager {
    var allSwiftFilesInProjectDirectory: [String] = []
    var convertToSwiftOnePointTwo: Bool = false
    var verboseLogging: Bool = false

    func shouldConvert() -> Bool {
        let path = "\(NSTask().currentDirectoryPath)/ConverterFlags.plist"
        if NSFileManager.defaultManager().fileExistsAtPath(path) {
            if var dictionary = NSDictionary(contentsOfFile: path) as? Dictionary<String, Bool> {
                if let isConvertedToNewSwift = dictionary["isConvertedToNewSwift"] {
                    var shouldConvert: Bool = (isConvertedToNewSwift != convertToSwiftOnePointTwo)
                    if shouldConvert {
                        dictionary["isConvertedToNewSwift"] = !isConvertedToNewSwift
                        NSDictionary(dictionary: dictionary).writeToFile(path, atomically: true)
                    }

                    return isConvertedToNewSwift != convertToSwiftOnePointTwo
                }
            }
        } else {
            let dictionary = NSDictionary(dictionary: ["isConvertedToNewSwift" : convertToSwiftOnePointTwo])
            dictionary.writeToFile(path, atomically: true)
        }
        return true
    }

    func beginConversion() {
        if shouldConvert() {
            let currentDirectory = NSTask().currentDirectoryPath
            if let printDirectoryArray = NSFileManager.defaultManager().contentsOfDirectoryAtPath(currentDirectory, error: nil) as? [String] {
                traverseThroughDirectories(printDirectoryArray, currentDirectory: currentDirectory)

                for swiftPath in allSwiftFilesInProjectDirectory {
                    if let swiftFileURL = NSURL(fileURLWithPath: swiftPath) {
                        var error: NSError?
                        if let swiftContents = NSString(contentsOfURL: swiftFileURL, encoding: NSUTF8StringEncoding, error: &error) {
                            editSwiftCodeAtPath(swiftFileURL)
                        }
                        if error != nil {
                            initiateEchoSequence("Could not access content of file \(swiftFileURL)", verbose: verboseLogging)
                        }
                    }
                }
            }
        }
    }

    func traverseThroughDirectories(directories: [String], currentDirectory: String) {
        for path in directories {
            if path.rangeOfString(".", options: .BackwardsSearch, range: path.rangeOfString(path), locale: nil) != nil {
                if path.rangeOfString(".swift", options: .BackwardsSearch, range: path.rangeOfString(path), locale: nil) != nil {
                    if path.rangeOfString(".orig", options: .BackwardsSearch, range: path.rangeOfString(path), locale: nil) == nil {
                        allSwiftFilesInProjectDirectory.append("\(currentDirectory)/\(path)")
                    }
                }
            } else {
                //Not a swift file. Go into the folder
                let pathDirectory = "\(currentDirectory)/\(path)"
                if let printDirectoryArray = NSFileManager.defaultManager().contentsOfDirectoryAtPath(pathDirectory, error: nil) as? [String] {
                    traverseThroughDirectories(printDirectoryArray, currentDirectory: pathDirectory)
                }
            }
        }
    }

    func editSwiftCodeAtPath(swiftFileURL: NSURL, shouldComment: Bool = true) {
        //To prevent loading the entire file to memory twice, we want to create a file stream buffer to read the file line by line. Doing so allows us to store an array of lines that need to be edited while still being memory efficient.
        if !shouldComment {
            initiateEchoSequence("Converting swift file at \(swiftFileURL.absoluteString!)", verbose: verboseLogging)
        }

        var linesToComment: [NSRange] = []
        var linesToUncomment: [NSRange] = []

        var fileWillBeConverted: Bool = false

        if let fileCrawler = FileCrawler(URL: swiftFileURL) {
            var newSwiftCode: String = ""
            var oldSwiftCode: String = ""
            var lineIsNewSwiftCode: Bool = false
            var lineIsOldSwiftCode: Bool = false

            for line in fileCrawler {
                if line.contains("#!/usr/bin/env xcrun swift") {
                    //Then we are in this file. We don't want to edit this file.
                    return
                }
                if line.contains("==Swift 1.2 Code==") {
                    fileWillBeConverted = true

                    lineIsNewSwiftCode = true
                    lineIsOldSwiftCode = false

                    newSwiftCode = ""
                    oldSwiftCode = ""
                    continue
                }
                if line.contains("==Old Swift Code==") {
                    lineIsNewSwiftCode = false
                    lineIsOldSwiftCode = true
                    continue
                }
                if line.contains("==End==") {
                    lineIsNewSwiftCode = false
                    lineIsOldSwiftCode = false

                    continue
                }
                if convertToSwiftOnePointTwo {
                    if lineIsNewSwiftCode && !shouldComment {
                        //Check to make sure it isn't already uncommented.
                        if line.hasPrefix("//") {
                            linesToUncomment.append(NSMakeRange(fileCrawler.currentRange.location, 2))
                        }
                    }
                    if lineIsOldSwiftCode && shouldComment {
                        //Check to make sure it isn't already commented
                        linesToComment.append(NSMakeRange(fileCrawler.currentRange.location, 2))
                    }
                } else {
                    if lineIsNewSwiftCode && shouldComment {
                        linesToComment.append(NSMakeRange(fileCrawler.currentRange.location, 2))
                    }
                    if lineIsOldSwiftCode && !shouldComment {
                        if line.hasPrefix("//") {
                            linesToUncomment.append(NSMakeRange(fileCrawler.currentRange.location, 2))
                        }
                    }
                }
            }
            fileCrawler.close()
        }

        if fileWillBeConverted {
            //Because we don't want to edit a file while it's being read in case of corruption, we are going to edit a file the same way file systems do; we save a copy of the file first, edit that file, and then replace the original file. Because of this we have to load the entire contents of the file.
            var error: NSError?
            if var swiftCode: NSMutableString = NSMutableString(contentsOfURL: swiftFileURL, encoding: NSUTF8StringEncoding, error: nil) {
                //Let's apply our changes!
                if shouldComment {
                    for lineCommentRange in reverse(linesToComment) {
                        swiftCode.insertString("//", atIndex: lineCommentRange.location)
                    }
                } else {
                    for lineUncommentRange in reverse(linesToUncomment) {
                        swiftCode.replaceCharactersInRange(lineUncommentRange, withString: "")
                    }
                }

                var writeError: NSError?
                swiftCode.writeToURL(swiftFileURL, atomically: true, encoding: NSUTF8StringEncoding, error: &writeError)

                if writeError != nil {
                    initiateEchoSequence("Could not write to file \(swiftFileURL)", verbose: verboseLogging)
                }
                if shouldComment {
                    //Ok. We successfully commented out our code. Now let's ucomment the areas that need to be uncommented.
                    editSwiftCodeAtPath(swiftFileURL, shouldComment: false)
                }
            }

            if error != nil {
                initiateEchoSequence("Could not read file \(swiftFileURL)", verbose: verboseLogging)
            }
        }
    }
}

//Start of script.
var suppliedNewArgument = false
var suppliedOldArgument = false
var suppliedVerboseArgument = false
var suppliedHelpArgument = false
var argumentsDoNotConflict = false

for argument in Process.arguments {
    if argument == "--new" || argument == "-n" {
        suppliedNewArgument = true
    }
    if argument == "--old" || argument == "-o" {
        suppliedOldArgument = true
    }
    if argument == "--verbose" || argument == "-v" {
        suppliedVerboseArgument = true
    }
    if argument == "--help" || argument == "-h" {
        suppliedHelpArgument = true
    }
}
argumentsDoNotConflict = (suppliedNewArgument != suppliedOldArgument) || (suppliedHelpArgument && Process.arguments.count == 2)

if Process.arguments.count < 4 {
    if Process.arguments.count > 0 {
        if argumentsDoNotConflict {
            if suppliedHelpArgument {
                initiateEchoSequence("Arguments:\n-n-new = Convert Code to Swift 1.2\n-o -old = Convert Code to Swift 1.1\n-h -help = Launch Help Text\n-v -verbose = Log Actions as they happen.\n\nThis script is used as an assistance tool. It recursively iterates through every child folder in your current directory (including your current directory) and switches commented values in each swift file that is wrapped in a #if-#else-#endif code block. You need to make sure you have a build environment variable called 'newSwift'.\n\nExample use case:\n\n\(pink)let\(endColor) a: \(magenta)NSString\(endColor) = \(red)\"Hector is AWESOMESAUCE\"\(endColor)\n\(brown)#if newSwift\(endColor)\n\(green)//Swift 1.2 Syntax\n//let b: String = a as! String\(endColor)\n\(brown)#else\(endColor)\n\(green)//Swift 1.1 Syntax\(endColor)\n\(pink)let\(endColor) b: \(magenta)String\(endColor) = a \(pink)as\(endColor) \(magenta)NSString\(endColor)\n\(brown)#endif\(endColor)\n\nProviding -new or -n as an argument will ensure all code wrapped in a '#if newSwift' scope will be uncommented and the code wrapped in the '#else' scope will commented out.\nThis will produce this output:\n\n\(pink)let\(endColor) a: \(magenta)NSString\(endColor) = \(red)\"Hector is AWESOMESAUCE\"\(endColor)\n\(brown)#if newSwift\(endColor)\n\(green)//Swift 1.2 Syntax\(endColor)\n\(pink)let\(endColor) b: \(magenta)String\(endColor) = a \(pink)as!\(endColor) \(magenta)String\(endColor)\n\(brown)#else\(endColor)\n\(green)//Swift 1.1 Syntax\n//let b: String = a as String\(endColor)\n\(brown)#endif\(endColor)", verbose: suppliedVerboseArgument)
            } else {
                //Begin the conversion!
                let manager = TaskManager()
                manager.convertToSwiftOnePointTwo = suppliedNewArgument
                manager.verboseLogging = suppliedVerboseArgument

                if manager.convertToSwiftOnePointTwo {
                    initiateEchoSequence("Converting code to Swift 1.2 compliance.", verbose: true)
                } else {
                    initiateEchoSequence("Converting code to Swift 1.1 compliance.", verbose: true)
                }
                manager.beginConversion()
                performCleanOnWorkspace()
                println("FINISHED! Hooray for you. Have a cute dinosaur.\n\n        _ _\n      _(9(9)__        __/^\\/^\\__\n     /o o   \\/_     __\\_\\_/\\_/_/_\n     \\___,   \\/_   _\\.'       './_      _/\\_\n      `---`\\  \\/_ _\\/           \\/_   _|.'_/\n            \\  \\/_\\/      /      \\/_  |/ /\n             \\  `-'      |        ';_:' /\n             /|          \\      \\     .'\n            /_/   |,___.-`',    /`'---`\n             /___/`       /____/\n\n")
            }
        } else {
            initiateEchoSequence("Invalid argument value. Protip: Use -help to see valid arguments!", verbose: true)
        }
    } else {
        if argumentsDoNotConflict {
            initiateEchoSequence("Please provide an argument. Protip: Use -help to see valid arguments!", verbose: true)
        } else {
            initiateEchoSequence("Arguments Conflict. Please use either -new or -o", verbose: true)
        }
    }
} else {
    initiateEchoSequence("Provided too many arguments. Please provide no arguments or provide --new to convert to Swift 1.2 and --old to convert to Swift 1.1", verbose: true)
}

