#
#  AppController.rb
#  iStac
#
#  Created by snaka on 08/09/28.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#
require 'pp'
require 'yaml'
require 'net/http'

require 'osx/cocoa'

require 'isbn_conv'
require 'PreferenceController'

OSX.ns_import :MyBarcodeScanner

class AppController < OSX::NSObject
  include ISBNConverter
  include OSX

  INITIAL_USER = "user"
  INITIAL_TOKEN = "api-token"
  
  OSX.ns_autorelease_pool do
    defaultValues = NSMutableDictionary.dictionary
    defaultValues[PreferenceController::USER_ID] = INITIAL_USER
    defaultValues[PreferenceController::API_TOKEN] = INITIAL_TOKEN
    NSUserDefaults.standardUserDefaults.registerDefaults(defaultValues)
  end

  ib_outlet :window, :isbn, :reqStatus, :title, :detailURL, 
            :status, :publication, :bookMsg, :result, 
            :image,
            :indicator, :message

  def initialize
    @screen = OSX::NSScreen.mainScreen.frame.size
  end
  
  # user defaults
  def user_id
    NSUserDefaults.standardUserDefaults[PreferenceController::USER_ID]
  end

  # get API token
  def api_token
    NSUserDefaults.standardUserDefaults[PreferenceController::API_TOKEN]
  end

  # Initalize window  
  def awakeFromNib
    if invalid_account? 
      self.openPreferences(nil)
    end
    
    @scanner = OSX::MyBarcodeScanner.sharedInstance
    @scanner.setStaysOpen(true)
    @scanner.setDelegate(self)
    @scanner.setMirrored(true)
    # start scan
    @scanner.scanForBarcodeWindow(nil)
    
    self.alignLeft
  end
  
  # Check account
  def invalid_account?
    return true if self.user_id == INITIAL_USER || self.api_token == INITIAL_TOKEN
    false
  end
  
  # register button
  def performRegistration(sender)
    ret = self.gotBarcode(@isbn.stringValue)
    puts "performRegistration: #{ret}"
  end
  ib_action :performRegistration

  # MyBarcodeScanner delegate method
  objc_method :gotBarcode, [:BOOL, :id]
  def gotBarcode(barcode)
    puts "*** barcode: #{barcode.to_s}"
    
    asin = barcode.to_s
    if asin.length > 10 
      begin
        asin = conv_isbn13to10(asin)
      rescue ArgumentError => ex
        puts "*** invalid barcode or scanning failure."
        puts ex
        return false
      end
    end
    
    if asin.length != 10 
      puts "*** Invalid ASIN's digit length expected 10 but was #{asin.length}."
      return false
    end
    
    puts "*** asin: #{asin}"
    @isbn.setStringValue(asin)
    return regist(asin)
  end
  
  # Menu action
  def openPreferences(sender)
    if @preferenceController.nil? then
      @preferenceController = PreferenceController.alloc.init
    end
    @preferenceController.showWindow(self)
  end
  ib_action :openPreferences

  # Move windows to right
  def alignRight
    puts "align to right"
    my_window = @window.frame.size
    left_align = OSX::NSRect.new(@screen.width - my_window.width, @screen.height - my_window.height, my_window.width, my_window.height)
    @window.setFrame_display_animate(left_align, true, true)
    
    isight = @scanner.iSightWindow.frame.size
    is_left_align = OSX::NSRect.new(@screen.width - isight.width, 0, isight.width, isight.height)
    @scanner.iSightWindow.setFrame_display_animate(is_left_align, true, false);
  end
  ib_action :alignRight
  
  # Move windows to left
  def alignLeft
    puts "align to left"
    my_window = @window.frame.size
    left_align = OSX::NSRect.new(0, @screen.height - my_window.height, my_window.width, my_window.height)
    @window.setFrame_display_animate(left_align, true, true)

    isight = @scanner.iSightWindow.frame.size
    is_right_align = OSX::NSRect.new(0, 0, isight.width, isight.height)
    @scanner.iSightWindow.setFrame_display_animate(is_right_align, true, false);
  end
  ib_action :alignLeft

  # Call API to regist book 
  def regist(isbn)
    # check 
    unless isbn.length == 10
      puts "*** ERROR: ISBN's digit must be 10."
      return false
    end

    clear_result
    @indicator.startAnimation(self)
    
    # Request to Stack Stock Books
    request = "[{\"asin\": \"#{isbn}\", \"state\": \"#{self.selected_state}\"}]"
    puts request

    body = {}
    
    Net::HTTP.version_1_2
    Net::HTTP.start("stack.nayutaya.jp", 80) do |http|
      uri      = "/api/#{self.user_id}/#{self.api_token}/stocks/update.1"
      pp(uri)
      response = http.post(uri, "request=#{URI.encode(request)}")
      body     = YAML.load(decode(response.body))
      pp(body)
    end

    @indicator.stopAnimation(self)
    
    # Parse result
    unless body["success"] == true
      puts "*** Error response."
      @message.setStringValue("Failed to registration.")
      return false
    end

    bookResult = body["response"][0]

    unless body["response"][0]["success"] == true
      puts "*** Registering '#{@isbn.stringValue}' was failed."
      @bookMsg.setStringValue(bookResult["message"])
      @message.setStringValue(body["message"])
      return false
    end
    
    # Display result
    @result.setStringValue(bookResult["success"] ? "succeed": "failed")
    @title.setStringValue(bookResult["title"])
    @detailURL.setStringValue(bookResult["detail"])
    @publication.setStringValue(bookResult["public"] ? "public": "private")
    @status.setStringValue(bookResult["state"])

    @image.mainFrame.loadRequest(OSX::NSURLRequest.requestWithURL(OSX::NSURL.URLWithString(bookResult['image'])))
    
    @bookMsg.setStringValue(bookResult["message"])
    @message.setStringValue(body["message"])
    
    return true
  end
  
  # Get state string
  def selected_state
    ['wish', 'unread', 'reading', 'read'][@reqStatus.indexOfSelectedItem]
  end
  
  # Clear result for next 
  def clear_result
    @result.setStringValue("")
    @title.setStringValue("")
    @detailURL.setStringValue("")
    @publication.setStringValue("")
    @status.setStringValue("")
    @bookMsg.setStringValue("")
    @message.setStringValue("")
  end
  
  # decode japanese charactor code
  def decode(str)
    return str.gsub(/(\\u[A-Fa-f0-9]{4})+/) { |chars|
      NKF.nkf("-W16B -w80", chars.scan(/\\u([A-Fa-f0-9]{4})/).map { |char,| char.hex }.pack("n*"))
    }
  end
end
