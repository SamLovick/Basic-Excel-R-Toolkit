/**
 * Copyright (c) 2017-2018 Structured Data, LLC
 *
 * This file is part of BERT.
 *
 * BERT is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * BERT is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with BERT.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * text clipboard for the renderer. electron's clipboard module is no
 * longer available in renderer processes, and the standard web API is
 * what it recommends instead. both calls are asynchronous.
 */
export const clipboard = {

  writeText(text: string): Promise<void> {
    return navigator.clipboard.writeText(text);
  },

  readText(): Promise<string> {
    return navigator.clipboard.readText();
  }

};
