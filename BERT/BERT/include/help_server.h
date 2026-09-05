/**
 * Copyright (c) 2026 Structured Data, LLC
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

#pragma once

#include <string>

/**
 * serves the generated function help pages over loopback.
 *
 * excel's help topic (the "Help on this function" button in the Function
 * Arguments dialog) takes a URL or a .chm file, and nothing else: a path to
 * an html file on disk is not accepted. so pages generated from R comments
 * are served from here, and the topic is an address on 127.0.0.1.
 *
 * the listener binds to loopback only, serves GET for a single flat
 * directory, and only for names that look like the pages we generate. it
 * starts on demand -- if no function has help, no socket is opened.
 */
class HelpServer {

public:

  /**
   * starts the listener if it isn't already running, serving files from
   * `root` (which should end with a separator). returns the port, or 0 if
   * the listener could not be started. calls after the first are cheap and
   * keep the original root.
   */
  static int Start(const std::string &root);

  /** port we are listening on, or 0 if not running */
  static int port();

  /**
   * address for a generated page, or an empty string if the server isn't
   * running. the name is not escaped: generated names are ascii.
   */
  static std::string UrlFor(const std::string &file);

  /** stops the listener, if it's running. */
  static void Stop();

};
