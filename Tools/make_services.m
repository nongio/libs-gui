/* This tool builds a cache of service specifications like the
   NeXTstep/ OPENSTEP 'make_services' tool.  In addition it builds a list of
   applications and services-bundles found in the standard directories.

   Copyright (C) 1998 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: November 1998

   This file is part of the GNUstep Project

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.
    
   You should have received a copy of the GNU General Public  
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   */

#include	<Foundation/NSArray.h>
#include	<Foundation/NSBundle.h>
#include	<Foundation/NSDictionary.h>
#include	<Foundation/NSFileManager.h>
#include	<Foundation/NSString.h>
#include	<Foundation/NSProcessInfo.h>
#include	<Foundation/NSData.h>
#include	<Foundation/NSDebug.h>
#include	<Foundation/NSDistributedLock.h>
#include	<Foundation/NSAutoreleasePool.h>
#include	<Foundation/NSPathUtilities.h>
#include	<Foundation/NSSerialization.h>

static void scanDirectory(NSMutableDictionary *services, NSString *path);
static void scanDynamic(NSMutableDictionary *services, NSString *path);
static NSMutableArray *validateEntry(id svcs, NSString* path);
static NSMutableDictionary *validateService(NSDictionary *service, NSString* path, unsigned i);

static NSString		*appsName = @".GNUstepAppList";
static NSString		*cacheName = @".GNUstepServices";

static	BOOL verbose = NO;
static	NSMutableDictionary	*serviceMap;
static	NSMutableDictionary	*filterMap;
static	NSMutableDictionary	*printMap;
static	NSMutableDictionary	*spellMap;
static	NSMutableDictionary	*applicationMap;
static	NSMutableDictionary	*extensionsMap;

static Class aClass;
static Class dClass;
static Class sClass;

int
main(int argc, char** argv, char **env_c)
{
  NSAutoreleasePool	*pool;
  NSData		*data;
  NSProcessInfo		*proc;
  NSFileManager		*mgr;
  NSDictionary		*env;
  NSMutableDictionary	*services;
  NSMutableArray	*roots;
  NSArray		*args;
  NSArray		*locations;
  NSString		*usrRoot;
  NSString		*str;
  unsigned		index;
  BOOL			isDir;
  BOOL			usedPrefixes = NO;
  NSMutableDictionary	*fullMap;
  NSDictionary		*oldMap;

#ifdef GS_PASS_ARGUMENTS
  [NSProcessInfo initializeWithArguments:argv count:argc environment:env_c];
#endif
  pool = [NSAutoreleasePool new];

  aClass = [NSArray class];
  dClass = [NSDictionary class];
  sClass = [NSString class];

  proc = [NSProcessInfo processInfo];
  if (proc == nil)
    {
      NSLog(@"unable to get process information!\n");
      [pool release];
      exit(EXIT_SUCCESS);
    }

  [NSSerializer shouldBeCompact: YES];

  serviceMap = [NSMutableDictionary dictionaryWithCapacity: 64];
  filterMap = [NSMutableDictionary dictionaryWithCapacity: 66];
  printMap = [NSMutableDictionary dictionaryWithCapacity: 8];
  spellMap = [NSMutableDictionary dictionaryWithCapacity: 8];
  applicationMap = [NSMutableDictionary dictionaryWithCapacity: 64];
  extensionsMap = [NSMutableDictionary dictionaryWithCapacity: 64];

  env = [proc environment];
  args = [proc arguments];

  for (index = 1; index < [args count]; index++)
    {
      if ([[args objectAtIndex: index] isEqual: @"--verbose"])
	{
	  verbose = YES;
	}
      if ([[args objectAtIndex: index] isEqual: @"--help"])
	{
	  printf(
"make_services builds a validated cache of service information for use by\n"
"programs that want to use the OpenStep services facility.\n"
"This cache is stored in '%s' in the users GNUstep directory.\n"
"\n"
"You may use 'make_services --test filename' to test that the property list\n"
"in 'filename' contains a valid services definition.\n"
"You may use 'make_services --verbose' to produce descriptive output.\n",
[cacheName cString]);
	  exit(EXIT_SUCCESS);
	}
      if ([[args objectAtIndex: index] isEqual: @"--test"])
	{
	  verbose = YES;
	  while (++index < [args count])
	    {
	      NSString		*file = [args objectAtIndex: index];
	      NSDictionary	*info;

	      info = [NSDictionary dictionaryWithContentsOfFile: file];
	      if (info)
		{
		  id	svcs = [info objectForKey: @"NSServices"];

		  if (svcs)
		    {
		      validateEntry(svcs, file);
		    }
		  else
		    {
		      NSLog(@"bad info - %@\n", file);
		    }
		}
	      else
		{
		  NSLog(@"bad info - %@\n", file);
		}
	    }
	  exit(EXIT_SUCCESS);
	}
    }

  roots = [NSMutableArray arrayWithCapacity: 3];

  /*
   *	Set up an array of root paths from the prefix list if possible.
   *	If we managed to get any paths, we set a flag so we know not to
   *	get and add default values later.
   */
  str = [env objectForKey: @"GNUSTEP_PATHPREFIX_LIST"];
  if (str != nil && [str isEqualToString: @""] == NO)
    {
      NSArray	*a = [str componentsSeparatedByString: @":"];
      unsigned	index;

      for (index = 0; index < [a count]; index++)
	{
	  str = [a objectAtIndex: index];
	  if ([str isEqualToString: @""] == NO)
	    {
	      if ([roots containsObject: str] == NO)
		{
		  [roots addObject: str];
		  usedPrefixes = YES;
		}
	    }
	}
    }

  services = [NSMutableDictionary dictionaryWithCapacity: 200];

  /*
   *	Build a list of 'root' directories to search for applications.
   *	Order is important - later duplicates of services are ignored.
   *
   *	Make sure that the users 'GNUstep/Services' directory exists.
   */
  usrRoot = [NSSearchPathForDirectoriesInDomains(NSUserDirectory,
    NSUserDomainMask, YES) lastObject];

  mgr = [NSFileManager defaultManager];
  if (([mgr fileExistsAtPath: usrRoot isDirectory: &isDir] && isDir) == 0)
    {
      if ([mgr createDirectoryAtPath: usrRoot attributes: nil] == NO)
	{
	  NSLog(@"couldn't create %@\n", usrRoot);
	  [pool release];
	  exit(EXIT_FAILURE);
	}
    }

  str = usrRoot;	/* Record for adding into roots array */

  usrRoot = [str stringByAppendingPathComponent: @"Library/Services"];
  if (([mgr fileExistsAtPath: usrRoot isDirectory: &isDir] && isDir) == 0)
    {
      if ([mgr createDirectoryAtPath: usrRoot attributes: nil] == NO)
	{
	  NSLog(@"couldn't create %@\n", usrRoot);
	  [pool release];
	  exit(EXIT_FAILURE);
	}
    }

  if (usedPrefixes == NO)
    {
      /*
       * Ensure that the user root (or default user root) is in the path.
       */
      if ([roots containsObject: str] == NO)
	{
	  [roots addObject: str];
	}

      /*
       * Ensure that the local root (or default local root) is in the path.
       */
      str = [env objectForKey: @"GNUSTEP_LOCAL_ROOT"];
      if (str == nil)
	{
	  str = @"/usr/GNUstep/Local";
	}
      if ([roots containsObject: str] == NO)
	{
	  [roots addObject: str];
	}

      /*
       * Ensure that the system root (or default system root) is in the path.
       */
      str = [env objectForKey: @"GNUSTEP_SYSTEM_ROOT"];
      if (str == nil)
	{
	  str = @"/usr/GNUstep";
	}
      if ([roots containsObject: str] == NO)
	{
	  [roots addObject: str];
	}
    }

  /*
   *	Before doing the main scan, we examine the 'Services' directory to
   *	see if any application has registered dynamic services - these take
   *	precedence over any listed in an applications Info_gnustep.plist.
   */
  scanDynamic(services, usrRoot);

  /*
   *	List of directory names to search within each root directory
   *	when looking for applications providing services.
   */
  /* FIXME - Shouldn't this be asking to the gnustep-base library for
   * the list of application directories rather than try build its own
   * ? */
  locations = [NSArray arrayWithObjects: @"Applications", 
		       @"Library/Services", nil];

  for (index = 0; index < [roots count]; index++)
    {
      NSString		*root = [roots objectAtIndex: index];
      unsigned		dirIndex;

      for (dirIndex = 0; dirIndex < [locations count]; dirIndex++)
	{
	  NSString	*loc = [locations objectAtIndex: dirIndex];
	  NSString	*path = [root stringByAppendingPathComponent: loc];

	  scanDirectory(services, path);
	}
    }

  fullMap = [NSMutableDictionary dictionaryWithCapacity: 5];
  [fullMap setObject: services forKey: @"ByPath"];
  [fullMap setObject: serviceMap forKey: @"ByService"];
  [fullMap setObject: filterMap forKey: @"ByFilter"];
  [fullMap setObject: printMap forKey: @"ByPrint"];
  [fullMap setObject: spellMap forKey: @"BySpell"];

  str = [usrRoot stringByAppendingPathComponent: cacheName];
  if ([mgr fileExistsAtPath: str])
    {
      data = [NSData dataWithContentsOfFile: str];
      oldMap = [NSDeserializer deserializePropertyListFromData: data
					     mutableContainers: NO];
    }
  else
    {
      oldMap = nil;
    }
  if ([fullMap isEqual: oldMap] == NO)
    {
      data = [NSSerializer serializePropertyList: fullMap];
      if ([data writeToFile: str atomically: YES] == NO)
	{
	  NSLog(@"couldn't write %@\n", str);
	  [pool release];
	  exit(EXIT_FAILURE);
	}
    }

  str = [usrRoot stringByAppendingPathComponent: appsName];
  if ([mgr fileExistsAtPath: str])
    {
      data = [NSData dataWithContentsOfFile: str];
      oldMap = [NSDeserializer deserializePropertyListFromData: data
					     mutableContainers: NO];
    }
  else
    {
      oldMap = nil;
    }
  [applicationMap setObject: extensionsMap forKey: @"GSExtensionsMap"];
  if ([applicationMap isEqual: oldMap] == NO)
    {
      data = [NSSerializer serializePropertyList: applicationMap];
      if ([data writeToFile: str atomically: YES] == NO)
	{
	  NSLog(@"couldn't write %@\n", str);
	  [pool release];
	  exit(EXIT_FAILURE);
	}
    }

  [pool release];
  exit(EXIT_SUCCESS);
}

/*
 * Load information about the types of files that an application supports.
 * For each extension found, produce a dictionary, keyed by app name, that
 * contains dictionaries giving type info for that extension.
 * NB. in order to make extensions case-insensiteve - we always convert
 * to lowercase.
 */
static void addExtensionsForApplication(NSDictionary *info, NSString *app)
{
  unsigned int  i;
  id            o0;
  NSArray       *a0;


  o0 = [info objectForKey: @"NSTypes"];
  if (o0)
    {
      if ([o0 isKindOfClass: aClass] == NO)
        {
          NSLog(@"bad app NSTypes (not an array) - %@\n", app);
          return;
        }
      a0 = (NSArray*)o0;
      i = [a0 count];
      while (i-- > 0)
        {
          NSDictionary          *t;
          NSArray               *a1;
          id                    o1 = [a0 objectAtIndex: i];
          unsigned int          j;

          if ([o1 isKindOfClass: dClass] == NO)
            {
              NSLog(@"bad app NSTypes (type not a dictionary) - %@\n", app);
              return;
            }
	  /*
	   * Set 't' to the dictionary defining a particular file type.
	   */
          t = (NSDictionary*)o1;
          o1 = [t objectForKey: @"NSUnixExtensions"];
          if (o1 == nil)
            {
              continue;
            }
          if ([o1 isKindOfClass: aClass] == NO)
            {
              NSLog(@"bad app NSType (extensions not an array) - %@\n", app);
              return;
            }
          a1 = (NSArray*)o1;
          j = [a1 count];
          while (j-- > 0)
            {
              NSString			*e;
              NSMutableDictionary	*d;

              e = [[a1 objectAtIndex: j] lowercaseString];
	      if ([e length] == 0)
		{
		  NSLog(@"Illegal (nul) extension ignored for - %@\n", app);
		  return;
		}
              d = [extensionsMap objectForKey: e];
              if (d == nil)
                {
                  d = [NSMutableDictionary dictionaryWithCapacity: 1];
                  [extensionsMap setObject: d forKey: e];
                }
              if ([d objectForKey: app] == NO)
                {
                  [d setObject: t forKey: app];
                } 
            }
        }
    }
  else
    {
      /*
       *    If we have an old format list of extensions
       *    handled by this application - ensure that
       *    the name of the application is listed in
       *    the dictionary of applications handling each of
       *    the extensions.
       */
      o0 = [info objectForKey: @"NSExtensions"];
      if (o0 == nil)
        {
          return;
        }
      if ([o0 isKindOfClass: aClass] == NO)
        {
          NSLog(@"bad app NSExtensions (not an array) - %@\n", app);
          return;
        }
      a0 = (NSArray*)o0;
      i = [a0 count];
      while (i-- > 0)
        {
          NSString		*e;
          NSMutableDictionary	*d;

          e = [[a0 objectAtIndex: i] lowercaseString];
          d = [extensionsMap objectForKey: e];
          if (d == nil)
            {
	      d = [NSMutableDictionary dictionaryWithCapacity: 1];
	      [extensionsMap setObject: d forKey: e];
            }
          if ([d objectForKey: app] == nil)
            {
	      NSDictionary	*info;

	      info = [NSDictionary dictionaryWithObjectsAndKeys:
			nil];
              [d setObject: info forKey: app];
            } 
        }
    }
}

static void
scanDirectory(NSMutableDictionary *services, NSString *path)
{
  NSFileManager		*mgr = [NSFileManager defaultManager];
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];
  NSArray		*contents = [mgr directoryContentsAtPath: path];
  unsigned		index;

  for (index = 0; index < [contents count]; index++)
    {
      NSString	*name = [contents objectAtIndex: index];
      NSString	*ext = [name pathExtension];
      NSString	*newPath;
      BOOL	isDir;

      if (ext != nil
	&& ([ext isEqualToString: @"app"] || [ext isEqualToString: @"debug"]
	|| [ext isEqualToString: @"profile"]))
	{
	  newPath = [path stringByAppendingPathComponent: name];
	  if ([mgr fileExistsAtPath: newPath isDirectory: &isDir] && isDir)
	    {
	      NSString		*oldPath;
	      NSBundle		*bundle;
	      NSDictionary	*info;

	      /*
	       *	All application paths are noted by name
	       *	in the 'applicationMap' dictionary.
	       */
              if ((oldPath = [applicationMap objectForKey: name]) == nil)
                {
                  [applicationMap setObject: newPath forKey: name];
                }
              else
                {
                  /*
                   * If we already have an entry for an application with
                   * this name, we skip this one - the first one takes
                   * precedence.
                   */
                  NSLog(@"duplicate app (%@) at '%@' and '%@'\n",
		    name, oldPath, newPath);
                  continue;
                }

	      bundle = [NSBundle bundleWithPath: newPath];
	      info = [bundle infoDictionary];
	      if (info)
		{
		  id	obj;

		  /*
		   * Load and validate any services definitions.
		   */
		  obj = [info objectForKey: @"NSServices"];
		  if (obj)
		    {
		      NSMutableArray	*entry;

		      entry = validateEntry(obj, newPath);
		      if (entry)
			{
			  [services setObject: entry forKey: newPath];
			}
		    }

		  addExtensionsForApplication(info, name);
		}
	      else
		{
		  NSLog(@"bad app info - %@\n", newPath);
		}
	    }
	  else
	    {
	      NSLog(@"bad application - %@\n", newPath);
	    }
	}
      else if (ext != nil && [ext isEqualToString: @"service"])
	{
	  newPath = [path stringByAppendingPathComponent: name];
	  if ([mgr fileExistsAtPath: newPath isDirectory: &isDir] && isDir)
	    {
	      NSBundle		*bundle;
	      NSDictionary	*info;

	      bundle = [NSBundle bundleWithPath: newPath];
	      info = [bundle infoDictionary];
	      if (info)
		{
		  id	svcs = [info objectForKey: @"NSServices"];

		  if (svcs)
		    {
		      NSMutableArray	*entry;

		      entry = validateEntry(svcs, newPath);
		      if (entry)
			{
			  [services setObject: entry forKey: newPath];
			}
		    }
		  else
		    {
		      NSLog(@"missing info - %@\n", newPath);
		    }
		}
	      else
		{
		  NSLog(@"bad service info - %@\n", newPath);
		}
	    }
	  else
	    {
	      NSLog(@"bad services bundle - %@\n", newPath);
	    }
	}
      else
	{
	  newPath = [path stringByAppendingPathComponent: name];
	  if ([mgr fileExistsAtPath: newPath isDirectory: &isDir] && isDir)
	    {
	      scanDirectory(services, newPath);
	    }
	}
    }
  [arp release];
}

static void
scanDynamic(NSMutableDictionary *services, NSString *path)
{
  NSFileManager		*mgr = [NSFileManager defaultManager];
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];
  NSArray		*contents = [mgr directoryContentsAtPath: path];
  unsigned		index;

  for (index = 0; index < [contents count]; index++)
    {
      NSString		*name = [contents objectAtIndex: index];
      NSString		*infPath;
      NSDictionary	*info;

      /*
       *	Ignore anything with a leading dot.
       */
      if ([name hasPrefix: @"."])
	{
	  continue;
	}

      /* *.service bundles are handled in scanDirectory */
      if ([[name pathExtension] isEqualToString: @"service"])
	continue;

      infPath = [path stringByAppendingPathComponent: name];

      info = [NSDictionary dictionaryWithContentsOfFile: infPath];
      if (info)
	{
	  id	svcs = [info objectForKey: @"NSServices"];

	  if (svcs)
	    {
	      NSMutableArray	*entry;

	      entry = validateEntry(svcs, infPath);
	      if (entry)
		{
		  [services setObject: entry forKey: infPath];
		}
	    }
	}
      else
	{
	  NSLog(@"bad app info - %@\n", infPath);
	}
    }
  [arp release];
}

static NSMutableArray*
validateEntry(id svcs, NSString *path)
{
  NSMutableArray	*newServices;
  NSArray		*services;
  unsigned		pos;

  if ([svcs isKindOfClass: aClass] == NO)
    {
      NSLog(@"NSServices entry not an array - %@\n", path);
      return nil;
    }

  services = (NSArray*)svcs;
  newServices = [NSMutableArray arrayWithCapacity: [services count]];
  for (pos = 0; pos < [services count]; pos++)
    {
      id			svc;

      svc = [services objectAtIndex: pos];
      if ([svc isKindOfClass: dClass])
	{
	  NSDictionary		*service = (NSDictionary*)svc;
	  NSMutableDictionary	*newService;

	  newService = validateService(service, path, pos);
	  if (newService)
	    {
	      [newServices addObject: newService];
	    }
	}
      else
	{
	  NSLog(@"NSServices entry %u not a dictionary - %@\n",
	    pos, path);
	}
    }
  return newServices;
}

static NSMutableDictionary*
validateService(NSDictionary *service, NSString *path, unsigned pos)
{
  static NSDictionary	*fields = nil;
  NSEnumerator		*e;
  NSMutableDictionary	*result;
  NSString		*k;
  id			obj;

  if (fields == nil)
    {
      fields = [NSDictionary dictionaryWithObjectsAndKeys:
	@"string", @"NSMessage",
	@"string", @"NSPortName",
	@"array", @"NSSendTypes",
	@"array", @"NSReturnTypes",
	@"dictionary", @"NSMenuItem",
	@"dictionary", @"NSKeyEquivalent",
	@"string", @"NSUserData",
	@"string", @"NSTimeout",
	@"string", @"NSHost",
	@"string", @"NSExecutable",
	@"string", @"NSFilter",
	@"string", @"NSInputMechanism",
	@"string", @"NSPrintFilter",
	@"string", @"NSDeviceDependent",
	@"array", @"NSLanguages",
	@"string", @"NSSpellChecker",
	nil]; 
      [fields retain];
    }

  result = [NSMutableDictionary dictionaryWithCapacity: [service count]];

  /*
   *	Step through and check that each field is a known one and of the
   *	correct type.
   */
  e = [service keyEnumerator];
  while ((k = [e nextObject]) != nil)
    {
      NSString	*type = [fields objectForKey: k];

      if (type == nil)
	{
	  NSLog(@"NSServices entry %u spurious field (%@)- %@\n", pos, k, path);
	}
      else
	{
	  obj = [service objectForKey: k];
	  if ([type isEqualToString: @"string"])
	    {
	      if ([obj isKindOfClass: sClass] == NO)
		{
		  NSLog(@"NSServices entry %u field %@ is not a string "
		    @"- %@\n", pos, k, path);
		  return nil;
		}
	      [result setObject: obj forKey: k];
	    }
	  else if ([type isEqualToString: @"array"])
	    {
	      NSArray	*a;

	      if ([obj isKindOfClass: aClass] == NO)
		{
		  NSLog(@"NSServices entry %u field %@ is not an array "
		    @"- %@\n", pos, k, path);
		  return nil;
		}
	      a = (NSArray*)obj;
	      if ([a count] == 0)
		{
		  NSLog(@"NSServices entry %u field %@ is an empty array "
		    @"- %@\n", pos, k, path);
		}
	      else
		{
		  unsigned	i;

		  for (i = 0; i < [a count]; i++)
		    {
		      if ([[a objectAtIndex: i] isKindOfClass: sClass] == NO)
			{
			  NSLog(@"NSServices entry %u field %@ element %u is "
			    @"not a string - %@\n", pos, k, i, path);
			  return nil;
			}
		    }
		  [result setObject: a forKey: k];
		}
	    }
	  else if ([type isEqualToString: @"dictionary"])
	    {
	      NSDictionary	*d;

	      if ([obj isKindOfClass: dClass] == NO)
		{
		  NSLog(@"NSServices entry %u field %@ is not a dictionary "
		    @"- %@\n", pos, k, path);
		  return nil;
		}
	      d = (NSDictionary*)obj;
	      if ([d objectForKey: @"default"] == nil)
		{
		  NSLog(@"NSServices entry %u field %@ has no default value "
		    @"- %@\n", pos, k, path);
		}
	      else
		{
		  NSEnumerator	*e = [d objectEnumerator];

		  while ((obj = [e nextObject]) != nil)
		    {
		      if ([obj isKindOfClass: sClass] == NO)
			{
			  NSLog(@"NSServices entry %u field %@ contains "
			    @"non-string value - %@\n", pos, k, path);
			  return nil;
			}
		    }
		}
	      [result setObject: d forKey: k];
	    }
	}
    }

  /*
   *	Record in this service dictionary where it is to be found.
   */
  [result setObject: path forKey: @"ServicePath"];

  /*
   *	Now check that we have the required fields for the service.
   */
  if ((obj = [result objectForKey: @"NSMessage"]) != nil)
    {
      NSDictionary	*item;
      NSEnumerator	*e;
      NSString		*k;
      BOOL		used = NO;

      if ([result objectForKey: @"NSPortName"] == nil)
	{
	  NSLog(@"NSServices entry %u NSPortName missing - %@\n", pos, path);
	  return nil;
	}
      if ([result objectForKey: @"NSSendTypes"] == nil &&
	  [result objectForKey: @"NSReturnTypes"] == nil)
	{
	  NSLog(@"NSServices entry %u types missing - %@\n", pos, path);
	  return nil;
	}
      if ((item = [result objectForKey: @"NSMenuItem"]) == nil)
	{
	  NSLog(@"NSServices entry %u NSMenuItem missing - %@\n", pos, path);
	  return nil;
	}

      /*
       *	For each language, check to see if we already have a service
       *	by this name - if so - we ignore this one.
       */
      e = [item keyEnumerator];
      while ((k = [e nextObject]) != nil)
	{
	  NSString		*name = [item objectForKey: k];
	  NSMutableDictionary	*names;

	  names = [serviceMap objectForKey: k];
	  if (names == nil)
	    {
	      names = [NSMutableDictionary dictionaryWithCapacity: 1];
	      [serviceMap setObject: names forKey: k];
	    }
	  if ([names objectForKey: name] == nil)
	    {
	      [names setObject: result forKey: name];
	      used = YES;
	    }
	}
      if (used == NO)
	{
	  if (verbose)
	    {
	      NSLog(@"Ignoring entry %u in %@ -\n%@\n", pos, path, result);
	    }
	  return nil;	/* Ignore - already got service with this name	*/
	}
    }
  else if ((obj = [result objectForKey: @"NSFilter"]) != nil)
    {
      NSString	*str;
      NSArray	*snd;
      NSArray	*ret;
      unsigned	spos;
      BOOL	used = NO;

      str = [result objectForKey: @"NSInputMechanism"];
      if (str)
	{
	  if ([str isEqualToString: @"NSUnixStdio"] == NO &&
	      [str isEqualToString: @"NSMapFile"] == NO &&
	      [str isEqualToString: @"NSIdentity"] == NO)
	  {
	    NSLog(@"NSServices entry %u bad input mechanism - %@\n", pos, path);
	    return nil;
	  }
	}

      snd = [result objectForKey: @"NSSendTypes"];
      ret = [result objectForKey: @"NSReturnTypes"];
      if (snd == nil || ret == nil)
	{
	  NSLog(@"NSServices entry %u types missing - %@\n", pos, path);
	  return nil;
	}

      /*
       *	For each send-type/return-type combination, see if we
       *	already have a filter - if so - ignore this one.
       */
      spos = [snd count];
      while (spos-- > 0)
	{
	  NSString		*stype = [snd objectAtIndex: spos];
	  NSMutableDictionary	*sdict = [filterMap objectForKey: stype];
	  unsigned		rpos;

	  if (sdict == nil)
	    {
	      sdict = [NSMutableDictionary dictionaryWithCapacity: [snd count]];
	      [filterMap setObject: sdict forKey: stype];
	    }
	  rpos = [ret count];
	  while (rpos-- > 0)
	    {
	      NSString			*rtype = [ret objectAtIndex: rpos];

	      if ([sdict objectForKey: rtype] == nil)
		{
		  [sdict setObject: result forKey: rtype];
		  used = YES;
		}
	    }
	}
      if (used == NO)
	{
	  if (verbose)
	    {
	      NSLog(@"Ignoring entry %u in %@ -\n%@\n", pos, path, result);
	    }
	  return nil;	/* Ignore - already got filter for types.	*/
	}
    }
  else if ((obj = [result objectForKey: @"NSPrintFilter"]) != nil)
    {
      NSDictionary	*item;
      NSEnumerator	*e;
      NSString		*k;
      BOOL		used = NO;

      if ((item = [result objectForKey: @"NSMenuItem"]) == nil)
	{
	  NSLog(@"NSServices entry %u NSMenuItem missing - %@\n", pos, path);
	  return nil;
	}
      /*
       *	For each language, check to see if we already have a print
       *	filter by this name - if so - we ignore this one.
       */
      e = [item keyEnumerator];
      while ((k = [e nextObject]) != nil)
	{
	  NSString		*name = [item objectForKey: k];
	  NSMutableDictionary	*names;

	  names = [printMap objectForKey: k];
	  if (names == nil)
	    {
	      names = [NSMutableDictionary dictionaryWithCapacity: 1];
	      [printMap setObject: names forKey: k];
	    }
	  if ([names objectForKey: name] == nil)
	    {
	      [names setObject: result forKey: name];
	      used = YES;
	    }
	}
      if (used == NO)
	{
	  if (verbose)
	    {
	      NSLog(@"Ignoring entry %u in %@ -\n%@\n", pos, path, result);
	    }
	  return nil;	/* Ignore - already got filter with this name	*/
	}
    }
  else if ((obj = [result objectForKey: @"NSSpellChecker"]) != nil)
    {
      NSArray	*item;
      unsigned	pos;
      BOOL	used = NO;

      if ((item = [result objectForKey: @"NSLanguages"]) == nil)
	{
	  NSLog(@"NSServices entry %u NSLanguages missing - %@\n", pos, path);
	  return nil;
	}
      /*
       *	For each language, check to see if we already have a spell
       *	checker by this name - if so - we ignore this one.
       */
      pos = [item count];
      while (pos-- > 0)
	{
	  NSString	*lang = [item objectAtIndex: pos];

	  if ([spellMap objectForKey: lang] == nil)
	    {
	      [spellMap setObject: result forKey: lang];
	      used = YES;
	    }
	}
      if (used == NO)
	{
	  if (verbose)
	    {
	      NSLog(@"Ignoring entry %u in %@ -\n%@\n", pos, path, result);
	    }
	  return nil;	/* Ignore - already got speller with language.	*/
	}
    }
  else
    {
      NSLog(@"NSServices entry %u unknown service/filter - %@\n", pos, path);
      return nil;
    }
  
  return result;
}

