.pragma library

var presets = [
    { id: "compact", width: 180, maximumHeight: 113 },
    { id: "standard", width: 220, maximumHeight: 138 },
    { id: "enlarged", width: 260, maximumHeight: 163 },
    { id: "large", width: 320, maximumHeight: 200 },
]

function indexFor(width, maximumHeight) {
    for (var i = 0; i < presets.length; ++i) {
        if (presets[i].width === width && presets[i].maximumHeight === maximumHeight)
            return i
    }
    return -1
}

function sizeForIndex(index) {
    return index >= 0 && index < presets.length ? presets[index] : null
}

function apply(index, settings) {
    var preset = sizeForIndex(index)
    if (!preset || !settings)
        return false
    settings.previewThumbnailSize = preset.width
    settings.previewMaximumHeight = preset.maximumHeight
    return true
}
