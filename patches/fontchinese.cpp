/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "common/file.h"
#include "graphics/big5.h"

#include "sci/sci.h"
#include "sci/graphics/screen.h"
#include "sci/graphics/fontchinese.h"

namespace Sci {

// Big5 font data file shipped alongside the game (part of the CHT patch).
static const char *kChineseFontFile = "pq3_big5.fnt";
// Rendered glyph box: Big5Font glyphs are 16px wide (kChineseTraditionalWidth).
static const int kBig5Width = 16;

// Hi-res (2x) Big5 font for the 640x400 upscaled display path. Format matches the
// low-res font but at 32x30: per glyph [u16 BE big5][30 rows * 4 bytes], 0xFFFF end.
static const char *kChineseHiresFontFile = "pq3_big5_hi.fnt";
static const int kHiWidth = 32;
static const int kHiHeight = 30;
static const int kHiRowBytes = kHiWidth / 8;               // 4
static const int kHiGlyphBytes = kHiHeight * kHiRowBytes;  // 120

GfxFontChinese::GfxFontChinese(ResourceManager *resMan, GfxScreen *screen, GuiResourceId resourceId)
	: _screen(screen), _resourceId(resourceId), _big5(nullptr), _big5Height(14), _hiresData(nullptr) {
	// Original SCI font for single-byte (ASCII / control) glyphs.
	_asciiFont = new GfxFontFromResource(resMan, screen, resourceId);

	Common::File fontFile;
	if (fontFile.open(kChineseFontFile)) {
		_big5 = new Graphics::Big5Font();
		_big5->loadPrefixedRaw(fontFile, _big5Height);
		_big5Height = _big5->getFontHeight();
	} else {
		warning("GfxFontChinese: could not open '%s'; Chinese glyphs will be blank", kChineseFontFile);
	}

	// Optional hi-res font, only meaningful in the 640x400 upscaled CHT display path.
	if (_screen->getUpscaledHires() == GFX_SCREEN_UPSCALED_640x400)
		loadHiresFont();
}

GfxFontChinese::~GfxFontChinese() {
	delete _big5;
	delete _asciiFont;
	free(_hiresData);
}

void GfxFontChinese::loadHiresFont() {
	Common::File f;
	if (!f.open(kChineseHiresFontFile))
		return;
	uint32 size = f.size();
	_hiresData = (byte *)malloc(size);
	if (!_hiresData || f.read(_hiresData, size) != size) {
		free(_hiresData);
		_hiresData = nullptr;
		return;
	}
	uint32 pos = 0;
	int count = 0;
	while (pos + 2 + kHiGlyphBytes <= size) {
		uint16 code = (_hiresData[pos] << 8) | _hiresData[pos + 1];
		if (code == 0xFFFF)
			break;
		_hiresOff[code] = pos + 2;
		pos += 2 + kHiGlyphBytes;
		++count;
	}
	debug(1, "GfxFontChinese: loaded %d hi-res glyphs", count);
}

// Draw a Big5 char at 2x straight into the 640x400 display buffer (crisp CJK).
bool GfxFontChinese::drawHires(uint16 point, int16 top, int16 left, byte color) {
	if (!_hiresData)
		return false;
	if (!_hiresOff.contains(point))
		return false;
	const byte *g = _hiresData + _hiresOff[point];
	const int16 dispLeft = left * 2;
	const int16 dispTop = top * 2;
	const uint16 dw = _screen->getDisplayWidth();
	const uint16 dh = _screen->getDisplayHeight();
	for (int gy = 0; gy < kHiHeight; ++gy) {
		const byte *row = g + gy * kHiRowBytes;
		const int16 sy = dispTop + gy;
		if (sy < 0 || sy >= dh)
			continue;
		for (int gx = 0; gx < kHiWidth; ++gx) {
			if (!((row[gx >> 3] >> (7 - (gx & 7))) & 1))
				continue;
			const int16 sx = dispLeft + gx;
			if (sx >= 0 && sx < dw)
				_screen->putPixelOnDisplay(sx, sy, color);
		}
	}
	return true;
}

GuiResourceId GfxFontChinese::getResourceId() {
	return _resourceId;
}

byte GfxFontChinese::getHeight() {
	byte asciiHeight = _asciiFont->getHeight();
	return MAX<byte>(asciiHeight, (byte)_big5Height);
}

// text16 tests this on the first (lead) byte before combining the pair.
bool GfxFontChinese::isDoubleByte(uint16 chr) {
	return (chr >= 0x81) && (chr <= 0xFE);
}

byte GfxFontChinese::getCharWidth(uint16 chr) {
	// chr may arrive either as a bare lead byte (during width scans) or as a
	// combined lead|(trail<<8) value (during drawing). Both mean a Big5 char.
	if (chr > 0xFF || isDoubleByte(chr))
		return kBig5Width;
	return _asciiFont->getCharWidth(chr);
}

byte GfxFontChinese::getCharHeight(uint16 chr) {
	if (chr > 0xFF || isDoubleByte(chr))
		return (byte)_big5Height;
	return _asciiFont->getHeight();
}

void GfxFontChinese::draw(uint16 chr, int16 top, int16 left, byte color, bool greyedOutput) {
	// Single-byte: delegate to the original SCI font (keeps ASCII pixel-identical).
	if (chr <= 0xFF) {
		_asciiFont->draw(chr, top, left, color, greyedOutput);
		return;
	}

	// Double-byte: chr == lead | (trail << 8); Big5Font wants (lead << 8) | trail.
	uint16 point = ((chr & 0xFF) << 8) | (chr >> 8);

	// In the 640x400 CHT display path, draw the glyph crisp at 2x into the display
	// buffer instead of nearest-upscaling the 16px logical glyph (rule 81).
	if (_screen->getUpscaledHires() == GFX_SCREEN_UPSCALED_640x400 && drawHires(point, top, left, color))
		return;

	byte glyph[kBig5Width * 16];
	memset(glyph, 0, sizeof(glyph));
	bool drawn = false;
	if (_big5)
		drawn = _big5->drawBig5Char(glyph, point, kBig5Width, _big5Height, kBig5Width,
		                            /*color*/ 1, /*outlineColor*/ 0, /*outline*/ false, /*bpp*/ 1);
	if (!drawn) {
		// Fall back to a placeholder so missing glyphs are visible, not silent.
		_asciiFont->draw('?', top, left, color, greyedOutput);
		return;
	}

	uint16 screenWidth = _screen->fontIsUpscaled() ? _screen->getDisplayWidth() : _screen->getWidth();
	uint16 screenHeight = _screen->fontIsUpscaled() ? _screen->getDisplayHeight() : _screen->getHeight();

	for (int y = 0; y < _big5Height; y++) {
		for (int x = 0; x < kBig5Width; x++) {
			if (!glyph[y * kBig5Width + x])
				continue;
			int screenX = left + x;
			int screenY = top + y;
			if (0 <= screenX && screenX < screenWidth && 0 <= screenY && screenY < screenHeight)
				_screen->putFontPixel(top, screenX, y, color);
		}
	}
}

} // End of namespace Sci
