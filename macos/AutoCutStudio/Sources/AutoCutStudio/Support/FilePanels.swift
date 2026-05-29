import AppKit
import Foundation
import UniformTypeIdentifiers

enum FilePanels {
    static func openAudio() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Podcast Audio"
        panel.allowedContentTypes = contentTypes(["m4a", "mp3", "wav", "flac"])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openProject() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open AutoCut Project"
        panel.allowedContentTypes = contentTypes(["json"])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openSRT() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import SRT"
        panel.allowedContentTypes = contentTypes(["srt"])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openMarkdownForImport() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Markdown Checkboxes"
        panel.message = "Cancel to import the SRT with all segments selected."
        panel.allowedContentTypes = contentTypes(["md", "markdown"])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveProject(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save AutoCut Project"
        panel.allowedContentTypes = contentTypes(["json"])
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveMP3(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export MP3"
        panel.allowedContentTypes = contentTypes(["mp3"])
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveSRT(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export SRT"
        panel.allowedContentTypes = contentTypes(["srt"])
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveMarkdown(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Markdown"
        panel.allowedContentTypes = contentTypes(["md"])
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func contentTypes(_ extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }
}
