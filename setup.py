from setuptools import setup, Extension
from Cython.Build import cythonize

extensions = [
    Extension("lzstr.BitString", ["src/BitString.pyx"]),
    Extension("lzstr.Exceptions", ["src/Exceptions.pyx"]),
    Extension("lzstr.LZString", ["src/LZString.pyx"]),
]

setup(
    ext_modules=cythonize(extensions, include_path=["_include"], compiler_directives={"language_level": "3"}),
)
