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

#include "stdafx.h"
#include "variable.pb.h"
#include "XLCALL.h"
#include "function_descriptor.h"
#include "bert.h"
#include "basic_functions.h"
#include "type_conversions.h"
#include "windows_api_functions.h"

#include "excel_api_functions.h"
#include "help_server.h"

#include <fstream>

void resetXlOper(LPXLOPER12 x)
{
  if (x->xltype == (xltypeStr | xlbitDLLFree) && x->val.str)
  {
    // we pass a static string with zero length -- don't delete that
    // FIXME: we do? where? 

    if (x->val.str[0]) delete[] x->val.str;
    x->val.str = 0;

  }
  else if ((x->xltype == xltypeMulti || x->xltype == (xltypeMulti | xlbitDLLFree)) && x->val.array.lparray)
  {
    // have to consider the case that there are strings
    // in the array, or even nested multis (not that that
    // is a useful thing to do, but it could happen)

    int len = x->val.array.columns * x->val.array.rows;
    for (int i = 0; i < len; i++) resetXlOper(&(x->val.array.lparray[i]));

    delete[] x->val.array.lparray;
    x->val.array.lparray = 0;

  }

  x->val.err = xlerrNull;
  x->xltype = xltypeNil;

}

void UnregisterFunctions(const std::string &language) {

  XLOPER12 register_id;
  int err;
  bool remove_all = (language == "");
  BERT *bert = BERT::Instance();
  for (auto entry : bert->function_list_) {
    if (remove_all || language == entry->language_name_) {
      register_id.xltype = xltypeNum;
      register_id.val.num = entry->register_id_;
      err = Excel12(xlfUnregister, 0, 1, &register_id);
      if (err) {
        DebugOut("Err unregistering function: %d\n", err);
      }

      // FIXME: name also needs to be removed. but this may or may not work -- see
      // https://msdn.microsoft.com/en-us/library/office/bb687866.aspx
      

      entry->register_id_ = 0;
    }
  }
}

/** escapes the five characters xml reserves, for use in an attribute */
std::string XMLEscape(const std::string &text) {
  std::string escaped;
  for (auto c : text) {
    switch (c) {
    case '&': escaped.append("&amp;"); break;
    case '<': escaped.append("&lt;"); break;
    case '>': escaped.append("&gt;"); break;
    case '"': escaped.append("&quot;"); break;
    case '\'': escaped.append("&apos;"); break;
    default: escaped.push_back(c);
    }
  }
  return escaped;
}

/**
 * address of a function's long-form help, or an empty string if it has
 * none. either the language handed us an address, or it generated a page
 * into <home>\help and we serve that ourselves -- excel help topics have
 * to be a URL or a .chm, so a file path on disk is no use. starting the
 * server here means it only ever runs if some function has help.
 */
std::string HelpTopic(const std::shared_ptr<FunctionDescriptor> &entry) {

  if (entry->help_url_.length()) return entry->help_url_;
  if (!entry->help_file_.length()) return "";

  std::string root = BERT::Instance()->home_directory();
  root.append("help\\");

  HelpServer::Start(root);
  return HelpServer::UrlFor(entry->help_file_);

}

/**
 * writes the registered functions, with their descriptions, in the format
 * the Excel-DNA IntelliSense add-in reads. that add-in shows the argument
 * tooltip Excel itself only provides for its own functions; excel gives an
 * add-in no way to do it. this file is what BERT contributes; see
 * docs/FUNCTION-HELP.md for how the two are connected.
 *
 * this costs nothing when the IntelliSense add-in is not installed, so it
 * is written whenever functions are registered.
 */
void WriteIntelliSenseFile() {

  BERT *bert = BERT::Instance();
  std::string path = bert->home_directory();
  path.append(INTELLISENSE_FILE_NAME);

  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file.good()) {
    DebugOut("could not write %s\n", path.c_str());
    return;
  }

  file << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
  file << "<!-- written by BERT when it registers functions; edits will be lost -->\r\n";
  file << "<IntelliSense xmlns=\"http://schemas.excel-dna.net/intellisense/1.0\">\r\n";
  file << "  <FunctionInfo>\r\n";

  for (auto entry : bert->function_list_) {

    auto language_service = bert->GetLanguageService(entry->language_key_);
    if (!language_service) continue;

    // the name excel knows the function by, which is what the tooltip has
    // to match: the language prefix, then the alias if there is one

    std::string name = language_service->prefix();
    name.append(".");
    name.append(entry->alias_.length() ? entry->alias_ : entry->name_);

    // the IntelliSense add-in turns HelpTopic into a link in the tooltip,
    // so long-form help is one click from the formula the user is typing

    std::string help_topic = HelpTopic(entry);

    file << "    <Function Name=\"" << XMLEscape(name)
         << "\" Description=\"" << XMLEscape(entry->description_) << "\"";
    if (help_topic.length()) file << " HelpTopic=\"" << XMLEscape(help_topic) << "\"";
    file << ">\r\n";

    for (auto argument : entry->arguments_) {
      std::string description = argument->description_;
      if (!description.length() && argument->default_value_.length()) {
        description = "Default ";
        description.append(argument->default_value_);
      }
      file << "      <Argument Name=\"" << XMLEscape(argument->name_)
           << "\" Description=\"" << XMLEscape(description) << "\" />\r\n";
    }

    file << "    </Function>\r\n";
  }

  file << "  </FunctionInfo>\r\n";
  file << "</IntelliSense>\r\n";

}

void RegisterFunctions() {

  LPXLOPER12 xlParm[32];
  XLOPER12 xlRegisterID;
  int err;

  BERT *bert = BERT::Instance();
  for (int i = 0; i < 32; i++) {
    xlParm[i] = new XLOPER12;
    xlParm[i]->xltype = xltypeMissing;
  }

  err = Excel12(xlGetName, xlParm[0], 0);
  if (err) {
    DebugOut("ERR getting dll name\n");

    // the rest of the calls will also fail, so you should bail out now 
    // (and clean up). OTOH this indicates a significant problem so we 
    // should just never reach this point.

  }
  int index = 1000;

  for (auto entry : bert->function_list_) {

    auto language_service = bert->GetLanguageService(entry->language_key_);

    std::stringstream ss;

    ss.clear();
    ss.str("");
    ss << "BERTFunctionCall" << index;
    Convert::StringToXLOPER(xlParm[1], ss.str(), false);
    Convert::StringToXLOPER(xlParm[2], "UQQQQQQQQQQQQQQQQ", false);

    ss.clear();
    ss.str("");

    // using alias here instead of name; call will still use name.

    ss << language_service->prefix();
    ss << ".";
    if (entry->alias_.length()) ss << entry->alias_;
    else ss << entry->name_;
    Convert::StringToXLOPER(xlParm[3], ss.str(), false);

    ss.clear();
    ss.str("");
    for (auto arg : entry->arguments_) ss << ", " << arg->name_;
    Convert::StringToXLOPER(xlParm[4], ss.str().c_str() + 2, false);

    Convert::StringToXLOPER(xlParm[5], "1", false);

    ss.clear();
    ss.str("");
    if (entry->category_.length()) ss << entry->category_;
    else ss << "Exported " << language_service->name() << " Functions";
    Convert::StringToXLOPER(xlParm[6], ss.str().c_str(), false);

    // xlParm[8] is the help topic, which excel opens from the "Help on this
    // function" button in the Function Arguments dialog. it has to be a URL
    // or a .chm topic, and both halves of "<topic>!<context id>" are
    // required; a page we serve ourselves is context 0. this slot used to
    // carry the registration index, which is not a topic and did nothing.

    std::string help_topic = HelpTopic(entry);
    if (help_topic.length()) {
      ss.clear();
      ss.str("");
      ss << help_topic << "!0";
      Convert::StringToXLOPER(xlParm[8], ss.str(), false);
    }
    else {
      xlParm[8]->xltype = xltypeMissing;
    }

    if(entry->description_.length()) Convert::StringToXLOPER(xlParm[9], entry->description_, false);
    else Convert::StringToXLOPER(xlParm[9], "Exported Function", false);

    for (int i = 10; i < 32; i++) {
      int index = i - 10;
      xlParm[i]->xltype = xltypeMissing;
      if (entry->arguments_.size() > index){
        if (entry->arguments_[index]->description_.length()) {
          Convert::StringToXLOPER(xlParm[i], entry->arguments_[index]->description_, false);
        }
        else if (entry->arguments_[index]->default_value_.length()) {
          std::string value = "Default ";
          value += entry->arguments_[index]->default_value_;
          Convert::StringToXLOPER(xlParm[i], value, false);
        }
      }
    }

    xlRegisterID.xltype = xltypeMissing;
    err = Excel12v(xlfRegister, &xlRegisterID, 32, xlParm);
    if (!err) {
      if( xlRegisterID.xltype == xltypeNum ) entry->register_id_ = (int32_t)xlRegisterID.val.num;
      else if( xlRegisterID.xltype == xltypeInt ) entry->register_id_ = (int32_t)xlRegisterID.val.w;
    }
    Excel12(xlFree, 0, 1, &xlRegisterID);

    for (int i = 1; i < 32; i++) {
      if (xlParm[i]->xltype & xltypeStr) delete[] xlParm[i]->val.str;
    }

    index++;
  }

  Excel12(xlFree, 0, 1, xlParm[0]);
  for (int i = 0; i < 32; i++) delete xlParm[i];

  WriteIntelliSenseFile();

}

bool ExcelRegisterLanguageCalls(const char *language_name, uint32_t language_key, bool generic) {

  int err;
  XLOPER12 register_id;
  std::vector<LPXLOPER12> arguments;
  XCHAR wide_string[128];

  WCHAR wide_name[128];
  size_t wide_name_length = MultiByteToWideChar(CP_UTF8, 0, language_name, strlen(language_name), wide_name, 128);
  wide_name[wide_name_length] = 0;

  // here we're assuming that all strings are < 255 characters.
  // these are the static strings defined in the header, not 
  // anything user-defined.

  const int max_string_length = 256;

  for (int i = 0; i < 16; i++) arguments.push_back(new XLOPER12);
  for (int i = 1; i < 16; i++) {
    arguments[i]->xltype = xltypeStr;
    arguments[i]->val.str = new XCHAR[max_string_length];
  }

  // get the library; store as the first argument

  Excel12(xlGetName, arguments[0], 0);

  for (int i = 0; i< 2; i++)
  {
    for (int j = 0; j < 15; j++)
    {
      int len = (int)wcslen(callTemplates[i][j]);
      assert(len < (max_string_length - 1));
      wcscpy_s(&(arguments[j + 1]->val.str[1]), max_string_length - 1, callTemplates[i][j]);
      arguments[j + 1]->val.str[0] = len;
    }

    // index 0: add numeric index (+1000)
    wsprintf(wide_string, L"%s%d", callTemplates[i][0], language_key + 1000);
    wcscpy_s(&(arguments[0 + 1]->val.str[1]), max_string_length - 1, wide_string);
    arguments[0 + 1]->val.str[0] = (XCHAR)wcslen(wide_string);

    // index 2: add language name string

    // UPDATE: support a generic call by _not_ appending the language name.
    // this is for backwards compatibility. the caller needs to pick a language.

    if(generic) wsprintf(wide_string, L"%s", callTemplates[i][2]);
    else wsprintf(wide_string, L"%s.%s", callTemplates[i][2], wide_name);

    wcscpy_s(&(arguments[2 + 1]->val.str[1]), max_string_length - 1, wide_string);
    arguments[2 + 1]->val.str[0] = (XCHAR)wcslen(wide_string);

    // ok
    
    register_id.xltype = xltypeMissing;
    err = Excel12v(xlfRegister, &register_id, 16, &(arguments[0]));
    Excel12(xlFree, 0, 1, &register_id);
  }

  Excel12(xlFree, 0, 1, arguments[0]);

  for (int i = 1; i < 16; i++) {
    delete[] arguments[i]->val.str;
  }

  for (auto argument : arguments) delete argument;

  return true;

}

bool RegisterBasicFunctions()
{
  int err;
  XLOPER12 register_id;
  std::vector<LPXLOPER12> arguments;

  // here we're assuming that all strings are < 255 characters.
  // these are the static strings defined in the header, not 
  // anything user-defined.

  const int max_string_length = 256;

  for (int i = 0; i < 16; i++) arguments.push_back(new XLOPER12);
  for (int i = 1; i < 16; i++) {
    arguments[i]->xltype = xltypeStr;
    arguments[i]->val.str = new XCHAR[max_string_length];
  }

  // get the library; store as the first argument

  Excel12(xlGetName, arguments[0], 0);

  for (int i = 0; funcTemplates[i][0]; i++)
  {
    for (int j = 0; j < 15; j++)
    {
      int len = (int)wcslen(funcTemplates[i][j]);
      assert(len < (max_string_length - 1));

      wcscpy_s(&(arguments[j + 1]->val.str[1]), max_string_length - 1, funcTemplates[i][j]);
      arguments[j + 1]->val.str[0] = len;
    }

    register_id.xltype = xltypeMissing;
    err = Excel12v(xlfRegister, &register_id, 16, &(arguments[0]));
    Excel12(xlFree, 0, 1, &register_id);
  }

  Excel12(xlFree, 0, 1, arguments[0]);

  for (int i = 1; i < 16; i++) {
    delete[] arguments[i]->val.str;
  }

  for (auto argument : arguments) delete argument;

  return true;
}

BOOL WINAPI xlAutoOpen(void)
{
  RegisterBasicFunctions();
  BERT *bert = BERT::Instance();
  bert->Init();
  bert->RegisterLanguageCalls();
  bert->MapFunctions();
  RegisterFunctions();
  return true;
}

void WINAPI xlAutoFree12(LPXLOPER12 pxFree)
{
  if (pxFree->xltype == (xltypeMulti | xlbitDLLFree)
    || pxFree->xltype == (xltypeStr | xlbitDLLFree)) resetXlOper(pxFree);
}

BOOL WINAPI xlAutoClose(void)
{
  BERT::Instance()->Close();
  return true;
}

LPXLOPER12 WINAPI xlAddInManagerInfo12(LPXLOPER12 action)
{
  static XLOPER12 info, int_action;
  static XCHAR name[] = L" Basic Excel R Toolkit (BERT)";

  XLOPER12 type;
  type.xltype = xltypeInt;
  type.val.w = xltypeInt; // ??

  Excel12(xlCoerce, &int_action, 2, action, &type);

  if (int_action.val.w == 1)
  {
    info.xltype = xltypeStr;
    name[0] = (XCHAR)(wcslen(name + 1));
    info.val.str = name;
  }
  else
  {
    info.xltype = xltypeErr;
    info.val.err = xlerrValue;
  }

  return (LPXLOPER12)&info;
}


