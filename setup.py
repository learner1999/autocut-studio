# Modified for AutoCut Studio: package metadata describes this forked desktop app.

import re
from pathlib import Path

from setuptools import find_packages, setup

ROOT = Path(__file__).parent


def read_version() -> str:
    init_py = ROOT / "autocut" / "__init__.py"
    match = re.search(r'__version__ = "([^"]+)"', init_py.read_text(encoding="utf-8"))
    if not match:
        raise RuntimeError("Could not read package version")
    return match.group(1)


requirements = [
    "ffmpeg-python",
    "moviepy<2",
    "openai-whisper",
    "opencc-python-reimplemented",
    "parameterized",
    "pydub",
    "srt",
    "torchaudio",
    "tqdm",
]

dev_requirements = [
    "black",
    "pytest",
]


setup(
    name="autocut-studio",
    version=read_version(),
    description="Local podcast and audio editor powered by AutoCut and Whisper",
    install_requires=requirements,
    project_urls={
        "Upstream AutoCut": "https://github.com/mli/autocut",
    },
    license="Apache-2.0",
    long_description=(ROOT / "README.md").read_text(encoding="utf-8"),
    long_description_content_type="text/markdown",
    extras_require={
        "all": ["openai", "faster-whisper"],
        "dev": dev_requirements,
        "openai": ["openai"],
        "faster": ["faster-whisper"],
    },
    packages=find_packages(exclude=["test", "test.*"]),
    python_requires=">=3.9",
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Operating System :: MacOS",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Multimedia :: Sound/Audio :: Editors",
    ],
    entry_points={
        "console_scripts": [
            "autocut = autocut.main:main",
        ]
    },
)
