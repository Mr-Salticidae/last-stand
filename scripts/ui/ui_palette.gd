class_name UiPalette
extends Object

# LAST STAND design tokens — sRGB Color constants
# 来源 private/design_drops/ui/.../README.md "Design Tokens"

const BG_0       := Color("#0A0606")
const BG_1       := Color("#0F0A0A")
const BG_2       := Color("#1F1410")
const BG_3       := Color("#2A1A14")
const LINE       := Color("#3A201A")
const LINE_SOFT  := Color("#2A1612")

const RED        := Color("#DA2E33")
const RED_DIM    := Color("#8C1A1A")
const RED_DEEP   := Color("#5A1010")
const ORANGE     := Color("#FF7350")
const CREAM      := Color("#FFEAD9")
const CREAM_DIM  := Color("#C9B7A4")
const CREAM_MUTE := Color("#7A6A5C")
const HAZARD_Y   := Color("#C8A23B")

# 常用半透明
static func panel_bg(alpha: float = 0.6) -> Color:
	return Color(BG_1.r, BG_1.g, BG_1.b, alpha)

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
