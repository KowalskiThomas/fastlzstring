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

# cython: language_level=3, boundscheck=False, wraparound=False

cdef Py_ssize_t _swap_bit_order_c(Py_ssize_t x, int bitcount) noexcept:
	cdef Py_ssize_t y = 0
	cdef int i
	for i in range(bitcount):
		if x & (1 << i):
			y |= 1 << (bitcount - 1 - i)
	return y

def _swap_bit_order(x: int, bitcount: int = 8) -> int:
	return _swap_bit_order_c(x, bitcount)

cdef class BitString:
	_BASE64 = { char: _swap_bit_order(index, 6) for (index, char) in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/") }
	_URI_COMPONENT = { char: _swap_bit_order(index, 6) for (index, char) in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-") }
	_INV_BASE64 = { value: key for (key, value) in _BASE64.items() }
	_INV_URI_COMPONENT = { value: key for (key, value) in _URI_COMPONENT.items() }

	def __init__(self) -> None:
		self._bs = bytearray()
		self._bitlen = 0
		self._pos = 0

	@property
	def bit_len(self) -> int:
		return self._bitlen

	def seek(self, Py_ssize_t pos) -> None:
		self._pos = pos

	cdef inline bint _get_bit_c(self, Py_ssize_t pos) noexcept:
		cdef Py_ssize_t bytepos = pos >> 3
		cdef int bitpos = 7 - <int>(pos & 7)
		if bytepos < <Py_ssize_t>len(self._bs):
			return (self._bs[bytepos] >> bitpos) & 1
		return 0

	def get_bit(self, Py_ssize_t pos) -> bool:
		return bool(self._get_bit_c(pos))

	cdef void _set_bit_c(self, Py_ssize_t pos, bint value) noexcept:
		cdef Py_ssize_t bytepos = pos >> 3
		cdef int bitpos = 7 - <int>(pos & 7)
		cdef Py_ssize_t missing = bytepos + 1 - <Py_ssize_t>len(self._bs)
		if missing > 0:
			self._bs += bytearray(missing)
		if value:
			self._bs[bytepos] |= <unsigned char>(1 << bitpos)
		else:
			self._bs[bytepos] &= <unsigned char>(~(1 << bitpos))
		if pos + 1 > self._bitlen:
			self._bitlen = pos + 1

	def set_bit(self, Py_ssize_t pos, int value) -> None:
		assert value in (0, 1)
		self._set_bit_c(pos, <bint>value)

	def append(self, int bit) -> None:
		assert bit in (0, 1)
		self._set_bit_c(self._bitlen, <bint>bit)

	cpdef void append_value(self, Py_ssize_t value, int bitcount):
		cdef int i
		cdef Py_ssize_t bytepos
		cdef int bitpos
		cdef Py_ssize_t needed = (self._bitlen + bitcount + 7) // 8 - <Py_ssize_t>len(self._bs)
		if needed > 0:
			self._bs += bytearray(needed)
		for i in range(bitcount):
			bytepos = self._bitlen >> 3
			bitpos = 7 - <int>(self._bitlen & 7)
			if value & (1 << i):
				self._bs[bytepos] |= <unsigned char>(1 << bitpos)
			else:
				self._bs[bytepos] &= <unsigned char>(~(1 << bitpos))
			self._bitlen += 1

	@property
	def remaining_bits(self) -> int:
		return self._bitlen - self._pos

	cpdef Py_ssize_t read_bits(self, int count):
		cdef Py_ssize_t result = 0
		cdef int i
		for i in range(count):
			if self._get_bit_c(self._pos + i):
				result |= <Py_ssize_t>(1 << i)
		self._pos += count
		return result

	def read_chars(self, int count) -> bytearray:
		cdef int i
		result = bytearray(count)
		for i in range(count):
			result[i] = self.read_bits(8)
		return result

	@classmethod
	def _from_6bit_alphabet(cls, str input_text, dict alphabet):
		cdef BitString bitstring = BitString()
		cdef Py_ssize_t bits
		for char in input_text:
			if char not in alphabet:
				break
			bits = alphabet[char]
			bitstring.append_value(bits, 6)
		return bitstring

	def _to_6bit_alphabet(self, dict alphabet) -> str:
		cdef Py_ssize_t char_count = (self._bitlen + 5) // 6
		cdef Py_ssize_t charno, index
		result = []
		self.seek(0)
		for charno in range(char_count):
			index = self.read_bits(6)
			result.append(alphabet[index])
		return "".join(result)

	@classmethod
	def from_base64(cls, str input_text):
		return cls._from_6bit_alphabet(input_text, cls._BASE64)

	@classmethod
	def from_url_component(cls, str input_text):
		return cls._from_6bit_alphabet(input_text, cls._URI_COMPONENT)

	@classmethod
	def from_bit_text(cls, str text):
		cdef BitString bitstring = BitString()
		for char in text:
			if char == "0":
				bitstring._set_bit_c(bitstring._bitlen, 0)
			elif char == "1":
				bitstring._set_bit_c(bitstring._bitlen, 1)
		return bitstring

	@classmethod
	def from_bytes(cls, bytes data):
		cdef BitString bitstring = BitString()
		bitstring._bs = bytearray(data)
		bitstring._bitlen = <Py_ssize_t>len(data) * 8
		return bitstring

	def to_base64(self) -> str:
		return self._to_6bit_alphabet(self._INV_BASE64)

	def to_url_component(self) -> str:
		return self._to_6bit_alphabet(self._INV_URI_COMPONENT)

	def to_text(self) -> str:
		cdef Py_ssize_t i
		return "".join("1" if self._get_bit_c(i) else "0" for i in range(self._bitlen))

	def __bytes__(self) -> bytes:
		return bytes(self._bs)

	def __eq__(self, object other) -> bool:
		if not isinstance(other, BitString):
			return NotImplemented
		return (self._bitlen == (<BitString>other)._bitlen) and (self._bs == (<BitString>other)._bs)

	def __repr__(self) -> str:
		return f"BitString<{self._bitlen} bits: {self.to_text()}>"
