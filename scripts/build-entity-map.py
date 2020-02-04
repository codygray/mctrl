#!/usr/bin/env python3

# Helper script for generating map of named entities for src/entity_map.h which
# is needed by the Markdown view control.
#
# It uses the file entities.json downloaded from this source:
# https://html.spec.whatwg.org/multipage/entities.json
#
# Output goes to stdout.

import json
import os
import sys

def is_expected_ent_form(key):
    return len(key) >= 2 and key[0] == '&' and key[-1] == ';'

def strip_decoration(key):
    if is_expected_ent_form(key):
        return key[1:-1]
    else:
        return key

# Convert codepoints so that they are compact and can be distinguished from
# the entity names (ASCII alnum chars). See comments in src/entity.c for more
# info about it.
def encode_codepoints(codepoints):
    all_bytes = []

    for c in codepoints:
        c_bytes = []

        while True:
            c_bytes.insert(0, 0x80 | (c & 0x3f))
            c = c >> 6
            if c == 0:
                break

        c_bytes[0] |= 0xc0;
        all_bytes.extend(c_bytes)

    return "".join("\\x{:02x}".format(b) for b in all_bytes)


self_path = os.path.dirname(os.path.realpath(__file__));
with open(self_path + '/data/entities.json', 'r') as infile:
    dict = json.load(infile)

    sys.stdout.write(
"""/* This file is generated by scripts/build-entity-map.h.
 * Do not modify it manually.
 */

/*
 * mCtrl: Additional Win32 controls
 * <https://github.com/mity/mctrl>
 * <https://mctrl.org>
 *
 * Copyright (c) 2019-2020 Martin Mitas
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

/* User of this header is supposed to #define a preprocessor macro
 * ENTITY_MAP_RECORD(name, value) which defines how to treat with all
 * the string literals provided here.
 *
 * Typical definition might be as follows in order to gnerate initializers
 * for some array of structures:
 *
 *      #define ENTITY_MAP_RECORD(name, value)       { (name), (value) },
 */
#ifndef ENTITY_MAP_RECORD
    #error Macro ENTITY_MAP_RECORD not defined.
#endif


"""
)

    for ent in sorted(dict, key=strip_decoration):
        # We are only interested in those starting with '&' and ending with
        # ';' because Markdown does not recognize entities which do not end
        # with semicolon.
        if not is_expected_ent_form(ent):
            continue

        name = strip_decoration(ent)
        codepoints = encode_codepoints(dict[ent]['codepoints'])

        sys.stdout.write('ENTITY_MAP_RECORD("{0}", "{1}")\n'.format(name, codepoints))