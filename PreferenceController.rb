#
#  PreferenceController.rb
#  iSSBClient
#
#  Created by snaka on 08/10/05.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

class PreferenceController < OSX::NSWindowController
  ib_outlet :userId, :apiToken
  
  def init
    initWithWindowNibName "Preferences"
    setWindowFrameAutosaveName "PrefWindow"
    return self
  end

  # action handling
  def cancel
    defaults = OSX::NSUserDefaults.standardUserDefaults
    @userId.setStringValue(defaults[USER_ID])
    @apiToken.setStringValue(defaults[API_TOKEN]) 

    close
  end
  ib_action :cancel
  
  def setPreference
    defaults = OSX::NSUserDefaults.standardUserDefaults
    defaults[USER_ID] = @userId.stringValue
    defaults[API_TOKEN] = @apiToken.stringValue
    
    close
  end
  ib_action :setPreference
  
  # window event handling
  USER_ID = "USER_ID"
  API_TOKEN = "API_TOKEN"
  def windowDidLoad
    puts "window has loaded"
    defaults = OSX::NSUserDefaults.standardUserDefaults
    @userId.setStringValue(defaults[USER_ID])
    @apiToken.setStringValue(defaults[API_TOKEN])
  end
  
  # delegated methods
  def windowWillClose(notify)
    puts "window will close"

    defaults = OSX::NSUserDefaults.standardUserDefaults
    @userId.setStringValue(defaults[USER_ID])
    @apiToken.setStringValue(defaults[API_TOKEN]) 
    puts @apiToken.stringValue
    puts @userId.stringValue
  end
  
end
