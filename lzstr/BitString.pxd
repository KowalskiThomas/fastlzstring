cdef class BitString:
    cdef bytearray _bs
    cdef Py_ssize_t _bitlen
    cdef Py_ssize_t _pos

    cdef inline bint _get_bit_c(self, Py_ssize_t pos) noexcept
    cdef void _set_bit_c(self, Py_ssize_t pos, bint value) noexcept
    cpdef void append_value(self, Py_ssize_t value, int bitcount)
    cpdef Py_ssize_t read_bits(self, int count)
