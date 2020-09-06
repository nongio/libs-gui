/* Implementation of class NSDictionaryController
   Copyright (C) 2020 Free Software Foundation, Inc.
   
   By: Gregory John Casamento
   Date: 24-08-2020

   This file is part of the GNUstep Library.
   
   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110 USA.
*/

#import "AppKit/NSDictionaryController.h"
  
@implementation NSDictionaryController

- (NSDictionaryControllerKeyValuePair *) newObject
{
  return nil;
}

- (NSDictionary *) localizedKeyDictionary
{
  return _localizedKeyDictionary;
}

- (void) setLocalizedKeyDictionary: (NSDictionary *)dict
{
  ASSIGNCOPY(_localizedKeyDictionary, dict);
}
  
- (NSString *) localizedKeyTable
{
  return _localizedKeyTable;
}

- (void) setLocalizedKeyTable: (NSString *)table
{
  ASSIGNCOPY(_localizedKeyTable, table);
}

  
- (NSArray *) includedKeys
{
  return _includedKeys;
}

- (void) setIncludedKeys: (NSArray *)includedKeys
{
  ASSIGNCOPY(_includedKeys, includedKeys);
}


- (NSArray *) excludedKeys
{
  return _excludedKeys;
}

- (void) setExcludedKeys: (NSArray *)excludedKeys
{
  ASSIGNCOPY(_excludedKeys, excludedKeys);
}

  
- (NSString *) initialKey
{
  return _initialKey;
}

- (void) setInitialKey: (NSString *)k
{
  ASSIGNCOPY(_initialKey, k);
}

  
- (id) initialValue
{
  return _initialValue;
}

- (void) setInitialValue: (id)v
{
  ASSIGNCOPY(_initialValue, v);
}

@end

@implementation NSDictionaryControllerKeyValuePair
  
- (BOOL) isExplicitlyIncluded
{
  return _explicitlyIncluded;
}


- (NSString *) key
{
  return _key;
}

- (void) setKey: (NSString *)key
{
  ASSIGNCOPY(_key, key);
}

  
- (NSString *) localizedKey
{
  return _localizedKey;
}

- (void) setLocalizedKey: (NSString *)key
{
  ASSIGNCOPY(_localizedKey, key);
}
  
- (id) value
{
  return _value;
}

- (void) setValue: (id)value
{
  ASSIGNCOPY(_value, value);
}
  
@end
