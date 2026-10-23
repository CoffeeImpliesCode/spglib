# Notices

## Upstream

spglib is distributed under the BSD 3-Clause licence. `COPYING` is the authoritative upstream text and is carried unmodified. The copyright attribution is `Copyright (c) 2024, Spglib team`.

```
Copyright (c) 2024, Spglib team

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of the <organization> nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT
HOLDER> BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

This downstream packaging does not replace the upstream licence: the BSD 3-Clause terms apply to the whole library, whether built from this repository or installed from an upstream release. Fork-authored files use the separate owner grant in `FORK-LICENSE.md`, also BSD 3-Clause.

| Path | Attribution and licence |
| --- | --- |
| `src/`, `include/`, `database/` | Upstream spglib; BSD-3-Clause under `COPYING`. `src/overlap.c` and `src/primitive.c` include the recorded fork patches; other files in these paths match the pin. |
| `src/base.h` | Upstream file with no SPDX identifier in the upstream source. |
| `test/`, `example/`, `fortran/`, `python/`, `ruby/`, `docs/`, `cmake/`, `.distro/`, and other carried upstream paths in `UPSTREAM.sha256` | Upstream material under BSD-3-Clause in `COPYING`. |
| `README.upstream.md` | Byte-for-byte upstream `README.md`; governed by `COPYING`, not the fork grant. |
| `patches/*.patch` | Fork-authored patch text under the fork grant; quoted upstream C remains under `COPYING`. |
| `UPSTREAM.sha256` | Digest lines record upstream or patched upstream bytes; `#` comment text is fork-authored and covered by the grant. |
| `.gitignore` | Upstream entries remain upstream; the appended fork block is covered by the grant. |
| Other fork-authored paths listed in `FORK-LICENSE.md` | Owner-authorized BSD-3-Clause grant; `BSD-3-Clause` is the SPDX identifier for newly authored source or build files. |

Upstream source files carry their own SPDX identifiers except `src/base.h`, which upstream omits. The data in `database/` and generated tables in `src/spg_database.c`, `src/msg_database.c`, and `src/sitesym_database.c` use the same BSD 3-Clause terms. No third-party code is bundled.
