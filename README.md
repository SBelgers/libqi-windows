# libqi-windows

Windows (MSVC) build of [Aldebaran's libqi](https://github.com/aldebaran/libqi)
and its [Python bindings](https://github.com/aldebaran/libqi-python), packaged
as a pip-installable wheel.

This lets you `import qi` on Windows to talk to NAO and Pepper robots — no
Linux VM required.

## Quick install (pre-built wheel)

```
pip install libqi-windows
```

Or from a GitHub release:

```
pip install libqi_windows-4.0.1-cp314-cp314-win_amd64.whl
```

> **Note:** The wheel contains native DLLs and is specific to a Python version
> and platform. Check the [Releases](https://github.com/SBelgers/libqi-windows/releases)
> page for available builds.

## Verify

```python
import qi
print(qi.__version__)  # 3.1.5

session = qi.Session()
session.connect("tcp://nao.local:9559")
tts = session.service("ALTextToSpeech")
tts.say("Hello from Windows!")
```

---

## Building from source

If you need a different Python version or want to modify the code, you can
rebuild everything yourself.

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Visual Studio 2022 Build Tools** | 17.x (MSVC 19.4x) | [visualstudio.microsoft.com](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) |
| **CMake** | ≥ 3.23 | `winget install Kitware.CMake` |
| **Conan** | 2.x | `pip install conan` |
| **Ninja** | any | `pip install ninja` |
| **Git** | any | `winget install Git.Git` |
| **Python** | ≥ 3.11, 64-bit | [python.org](https://www.python.org/downloads/) |

### Conan profile (first time only)

```
conan profile detect
```

Verify `~/.conan2/profiles/default` contains:

```ini
[settings]
arch=x86_64
build_type=Release
compiler=msvc
compiler.cppstd=17
compiler.runtime=dynamic
compiler.version=194        # adjust to your MSVC version
os=Windows
```

### Build steps

1. **Create and activate a virtualenv:**

   ```
   python -m venv c:\venvs\libqi-windows
   c:\venvs\libqi-windows\Scripts\activate
   pip install conan ninja
   ```

2. **Clone this repo:**

   ```
   git clone https://github.com/SBelgers/libqi-windows.git
   cd libqi-windows
   ```

3. **Run the build script** from a *Developer PowerShell for VS 2022*:

   ```powershell
   .\build_all.ps1
   ```

   This will:
   - Clone `libqi` (v4.0.1) and `libqi-python` (v3.1.5) into the parent dir
   - Apply the MSVC patches from `patches/`
   - Build both with Conan + CMake
   - Install the `qi` package into your active venv
   - Run a smoke test (`import qi`)

4. **Build a wheel** (optional, for distribution):

   ```
   python build_wheel.py
   ```

   The `.whl` file will be written to `dist/`.

5. **Upload to PyPI** (optional):

   ```
   pip install twine
   twine upload dist/libqi_windows-4.0.1-*.whl
   ```

   After uploading, anyone can install with `pip install libqi-windows`.

### Manual build (without the script)

If you prefer to run each step yourself:

```
cd ..

git clone --depth 1 --branch qi-framework-v4.0.1 https://github.com/aldebaran/libqi.git
cd libqi
for %f in (..\libqi-windows\patches\libqi\*.patch) do git am "%f"
conan install . -s build_type=Release --build=missing
cmake --preset conan-release
cmake --build --preset conan-release
cd ..

git clone --depth 1 --branch qi-python-v3.1.5 https://github.com/aldebaran/libqi-python.git
cd libqi-python
for %f in (..\libqi-windows\patches\libqi-python\*.patch) do git am "%f"
conan install . -s build_type=Release --build=missing
cmake --preset conan-release
cmake --build --preset conan-release
python install_local.py
```

> **Important:** Do NOT pass `-of build/release` to `conan install`. The
> `cmake_layout()` in the conanfile already creates the `build/release/`
> subdirectory. Passing it again causes a double-nested path and cmake will
> fail to find the generated presets.

## What's in the patches?

### libqi patches (applied to `qi-framework-v4.0.1`)

| Patch | What it fixes |
|-------|---------------|
| `0001` | Pin Boost to 1.82, comment out gtest requirement, fix uninitialised `revision` variable, skip GNU-specific cppstd on MSVC |
| `0002` | Add missing `#include <ostream>` to `qi/path.hpp` |
| `0003` | Suppress C4251/C4275 warnings, define `qi_EXPORTS` on OBJECT library, set `_WIN32_WINNT`, add Boost dynamic link defines |
| `0004` | Remove duplicate `QI_API` on `static inline` methods in SSL header |

### libqi-python patches (applied to `qi-python-v3.1.5`)

| Patch | What it fixes |
|-------|---------------|
| `0001` | Pin Boost to 1.82, add OpenSSL, use local libqi instead of Conan package, skip MSVC-incompatible `compiler.libcxx` |
| `0002` | Point CMake at local libqi build, copy Python files to build dir |
| `0003` | Use public `Py_IsFinalizing()` on Python ≥ 3.13, use `Py_ssize_t` instead of `ssize_t` for MSVC |
| `0004` | Add `install_local.py` script to install built files into site-packages |

## Why Boost 1.82?

Boost 1.83 changed the ABI of `boost::filesystem::directory_entry` and
`boost::locale::message_format`. When libqi (built against Boost 1.83 headers)
tries to call into the Boost 1.83 DLLs, two symbols are missing at runtime.
Boost 1.82 does not have this problem.

## License

The patches and build scripts in this repo are provided under the
[BSD-3-Clause](https://opensource.org/licenses/BSD-3-Clause) license, matching
the upstream libqi license.

libqi and libqi-python are Copyright (c) Aldebaran Robotics / SoftBank Robotics.
