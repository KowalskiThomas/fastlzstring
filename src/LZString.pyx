#	pylzstr - Native Python implementation of LZString string compression
#	Copyright (C) 2022-2022 Johannes Bauer
#	Copyright (C) 2026-2026 Thomas Kowalski
#
#	This file is part of pylzstr.
#
#	pylzstr is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; this program is ONLY licensed under
#	version 3 of the License, later versions are explicitly excluded.
#
#	pylzstr is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with pylzstr; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#	Johannes Bauer <JohannesBauer@gmx.de>
#	Thomas Kowalski <thom.kowa@gmail.com>

# cython: language_level=3

from lzstr.BitString cimport BitString
from .BitString import BitString as _BitString
from .Exceptions import LZStringDecompressionException

# Compile-time constants replacing the SpecialTokens enum
DEF LITERAL_BYTE   = 0
DEF LITERAL_WORD   = 1
DEF END_OF_STREAM  = 2

import enum

class SpecialTokens(enum.IntEnum):
	LiteralByte  = LITERAL_BYTE
	LiteralWord  = LITERAL_WORD
	EndOfStream  = END_OF_STREAM

cdef inline int _c_bit_length(unsigned int n) noexcept:
	cdef int r = 0
	while n:
		n >>= 1
		r += 1
	return r


cdef class LZStringDecompressor:
	cdef BitString _bs
	cdef object _result  # bytearray or None

	def __init__(self, BitString bs) -> None:
		self._bs = bs
		self._result = None

	def decompress(self) -> bytearray:
		if self._result is not None:
			return self._result

		cdef dict cdict = {0: None, 1: None, 2: None}
		cdef int token_bits, token
		cdef object data, last_data

		self._bs.seek(0)
		self._result = bytearray()
		last_data = None
		while True:
			token_bits = _c_bit_length(<unsigned int>len(cdict))
			if self._bs.remaining_bits < token_bits:
				raise LZStringDecompressionException(
					f"Unexpected end of compressed stream: need {token_bits} bits "
					f"but only {self._bs.remaining_bits} remain"
				)

			token = <int>self._bs.read_bits(token_bits)
			if token == LITERAL_BYTE or token == LITERAL_WORD:
				data = bytes(self._bs.read_chars(token + 1))
				cdict[len(cdict)] = data
			elif token == END_OF_STREAM:
				return self._result
			else:
				if token in cdict:
					data = cdict[token]
				elif token == len(cdict):
					data = last_data + bytearray([last_data[0]])
				else:
					raise LZStringDecompressionException(
						f"token {token} is not in compression dictionary: {cdict}"
					)

			self._result += data
			if last_data is not None:
				cdict[len(cdict)] = bytes(last_data + bytes([data[0]]))
			last_data = data

	@classmethod
	def decompress_from_bytes(cls, bytes data) -> bytearray:
		return cls(_BitString.from_bytes(data)).decompress()

	@classmethod
	def decompress_from_base64(cls, str b64data) -> bytearray:
		return cls(_BitString.from_base64(b64data)).decompress()

	@classmethod
	def decompress_from_url_component(cls, str urlcomponent, bint escape = True) -> bytearray:
		if not escape:
			urlcomponent = urlcomponent.replace(" ", "+")
		return cls(_BitString.from_url_component(urlcomponent)).decompress()


cdef class LZStringCompressor:
	cdef bytes _data
	cdef dict _cdict
	cdef set _not_emitted_yet
	cdef BitString _result
	cdef int _dictsize

	def __init__(self, bytes data) -> None:
		self._data = data
		self._cdict = None
		self._not_emitted_yet = set()
		self._result = None
		self._dictsize = 3

	@property
	def token_bits(self) -> int:
		return _c_bit_length(<unsigned int>(self._dictsize - 1))

	cdef void _emit(self, bytes pattern):
		cdef int tb = _c_bit_length(<unsigned int>(self._dictsize - 1))
		if pattern in self._not_emitted_yet:
			self._not_emitted_yet.discard(pattern)
			self._result.append_value(LITERAL_BYTE, tb)
			self._result.append_value(pattern[0], 8)
			self._dictsize += 2
		else:
			self._result.append_value(self._cdict[pattern], tb)
			self._dictsize += 1

	def compress(self) -> BitString:
		if self._result is not None:
			return self._result

		cdef bytes substring, combined_pattern
		cdef bytes pattern = b""

		self._result = _BitString()
		self._cdict = {}

		for byte_val in self._data:
			substring = bytes([byte_val])

			if substring not in self._cdict:
				self._not_emitted_yet.add(substring)
				self._cdict[substring] = len(self._cdict) + 3

			combined_pattern = pattern + substring
			if combined_pattern in self._cdict:
				pattern = combined_pattern
			else:
				self._emit(pattern)
				self._cdict[combined_pattern] = len(self._cdict) + 3
				pattern = substring

		if len(pattern) > 0:
			self._emit(pattern)

		self._result.append_value(END_OF_STREAM, _c_bit_length(<unsigned int>(self._dictsize - 1)))
		self._cdict = None
		return self._result

	@classmethod
	def compress_to_bytes(cls, bytes data) -> bytes:
		return bytes(cls(data).compress())

	@classmethod
	def compress_to_base64(cls, bytes data) -> str:
		return cls(data).compress().to_base64()

	@classmethod
	def compress_to_url_component(cls, bytes data, bint escape = True) -> str:
		result = cls(data).compress().to_url_component()
		if not escape:
			result = result.replace("+", " ")
		return result
