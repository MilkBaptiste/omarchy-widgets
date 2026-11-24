import QtQuick

// 8-bit lab mascot (10x10 sprite scaled with nearest-neighbour). Sprites: ./mascots/<slug>.png
// Unknown labs fall back to the robot. Use px in multiples of 10 for crisp pixels.
Image {
  id: mascot
  property string provider: ""
  property int px: 20
  readonly property var slugs: ({ spacexai: "xai", xai: "xai", openai: "openai", anthropic: "anthropic", google: "google",
                                  meta: "meta", deepseek: "deepseek", mistral: "mistral", alibaba: "alibaba", kimi: "kimi",
                                  moonshotai: "kimi", xiaomi: "xiaomi", nvidia: "nvidia" })
  readonly property string slug: slugs[String(provider).toLowerCase().replace(/[^a-z0-9]/g, "")] || "robot"
  source: Qt.resolvedUrl("mascots/" + slug + ".png")
  width: px; height: px
  smooth: false
  sourceSize.width: px; sourceSize.height: px
}
