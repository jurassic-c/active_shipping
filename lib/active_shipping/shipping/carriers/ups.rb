module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://www.ups.com'
      
      RESOURCES = {
        :rates => 'ups.app/xml/Rate',
        :track => 'ups.app/xml/Track',
        :shipment_confirm => 'ups.app/xml/ShipConfirm',
        :shipment_accept => 'ups.app/xml/ShipAccept'
      }
      
      PICKUP_CODES = {
        :daily_pickup => "01",
        :customer_counter => "03", 
        :one_time_pickup => "06",
        :on_call_air => "07",
        :suggested_retail_rates => "11",
        :letter_center => "19",
        :air_service_center => "20"
      }
      
      DEFAULT_SERVICES = {
        "01" => "UPS Next Day Air",
        "02" => "UPS Second Day Air",
        "03" => "UPS Ground",
        "07" => "UPS Worldwide Express",
        "08" => "UPS Worldwide Expedited",
        "11" => "UPS Standard",
        "12" => "UPS Three-Day Select",
        "13" => "UPS Next Day Air Saver",
        "14" => "UPS Next Day Air Early A.M.",
        "54" => "UPS Worldwide Express Plus",
        "59" => "UPS Second Day Air A.M.",
        "65" => "UPS Saver",
        "82" => "UPS Today Standard",
        "83" => "UPS Today Dedicated Courier",
        "84" => "UPS Today Intercity",
        "85" => "UPS Today Express",
        "86" => "UPS Today Express Saver"
      }
      
      CANADA_ORIGIN_SERVICES = {
        "01" => "UPS Express",
        "02" => "UPS Expedited",
        "14" => "UPS Express Early A.M."
      }
      
      MEXICO_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited",
        "54" => "UPS Express Plus"
      }
      
      EU_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited"
      }
      
      OTHER_NON_US_ORIGIN_SERVICES = {
        "07" => "UPS Express"
      }
      
      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]
      
      def requirements
        [:key, :login, :password]
      end
      
      def find_rates(origin, destination, packages, options={})
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        rate_request = build_rate_request(origin, destination, packages, options)
        response = commit(:rates, save_request(access_request + rate_request), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end
      
      def find_tracking_info(tracking_number, options={})
        options = @options.merge(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end

      def buy_shipping_labels(shipper, origin, destination, packages, options = {})
        shipment = Shipment.new(
          :shipper => shipper,
          :payer => (options[:payer] || shipper),
          :origin => origin,
          :destination => destination,
          :packages => packages,
          :number => options[:shipment_number],
          :service => (options[:service] || '03')
        )
        expected_price = options[:expected_price]
        price_epsilon = options[:price_epsilon] || Money.new(0)
        request = build_shipment_confirm_request(shipment)
        response = commit(:shipment_confirm, save_request(build_access_request + request), (options[:test] || false))
        parse_shipment_confirm(shipment, response)
        if shipment.price && (!expected_price || (shipment.price - expected_price) < price_epsilon)
          request = build_shipment_accept_request(shipment)
          response = commit(:shipment_accept, save_request(build_access_request + request), (options[:test] || false))
          parse_shipment_accept(shipment, response)
        end
        shipment
      end

      protected
      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_xml
      end
      
      def build_rate_request(origin, destination, packages, options={})
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end
          root_node << XmlNode.new('PickupType') do |pickup_type|
            pickup_type << XmlNode.new('Code', PICKUP_CODES[options[:pickup_type] || :daily_pickup])
            # not implemented: PickupType/PickupDetails element
          end
          # not implemented: CustomerClassification element
          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end
            
            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element                    
            #                   * Shipment/Service element                            
            #                   * Shipment/PickupDate element                         
            #                   * Shipment/ScheduledDeliveryDate element              
            #                   * Shipment/ScheduledDeliveryTime element              
            #                   * Shipment/AlternateDeliveryTime element              
            #                   * Shipment/DocumentsOnly element                      
            
            packages.each do |package|
              debugger if package.nil?
              shipment << build_package_node(package, origin)
            end
            
            # not implemented:  * Shipment/ShipmentServiceOptions element
            #                   * Shipment/RateInformation element
            
          end
          
        end
        xml_request.to_xml
      end

      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_xml
      end

      def build_location_node(name,location,options={})
        # not implemented:  * Shipment/Shipper/Name element
        #                   * Shipment/(ShipTo|ShipFrom)/CompanyName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/AttentionName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/TaxIdentificationNumber element
        location_node = XmlNode.new(name) do |location_node|
          unless location.name.blank?
            node_name = (name == 'Shipper' ? 'Name' : 'CompanyName')
            location_node << XmlNode.new(node_name, location.name)
            if node_name == 'CompanyName' && !location.attention.blank?
              location_node << XmlNode.new('AttentionName', location.attention)
            end
          end
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/,'')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/,'')) unless location.fax.blank?
          
          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end
          
          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) unless location.province.blank?
              # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
            # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end

      def build_package_node(package, origin)
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
        XmlNode.new("Package") do |package_node|
          
          # not implemented:  * Shipment/Package/PackagingType element
          #                   * Shipment/Package/Description element
          
          package_node << XmlNode.new("PackagingType") do |packaging_type|
            packaging_type << XmlNode.new("Code", '02')
          end
          
          package_node << XmlNode.new("Dimensions") do |dimensions|
            dimensions << XmlNode.new("UnitOfMeasurement") do |units|
              units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
            end
            [:length,:width,:height].each do |axis|
              value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
              dimensions << XmlNode.new(axis.to_s.capitalize, [value,0.1].max)
            end
          end
        
          package_node << XmlNode.new("PackageWeight") do |package_weight|
            package_weight << XmlNode.new("UnitOfMeasurement") do |units|
              units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
            end
            
            value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
            package_weight << XmlNode.new("Weight", [value,0.1].max)
          end
        
          # not implemented:  * Shipment/Package/LargePackageIndicator element
          #                   * Shipment/Package/ReferenceNumber element
          #                   * Shipment/Package/PackageServiceOptions element
          #                   * Shipment/Package/AdditionalHandling element  
        end
      end
      
      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []
        
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          rate_estimates = []
          
          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                service_name_for(origin, service_code),
                                :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                :service_code => service_code,
                                :packages => packages)
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request, :log_xml => options[:log_xml])
      end

      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          tracking_number, origin, destination = nil
          shipment_events = []
          
          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s
          
          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end
          
          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                                 (date = activity.get_text('Date'))
                time, date = time.to_s, date.to_s
                hour, minute, second = time.scan(/\d{2}/)
                year, month, day = date[0..3], date[4..5], date[6..7]
                Time.utc(year, month, day, hour, minute, second)
              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end
            
            shipment_events = shipment_events.sort_by(&:time)
            
            if origin
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end
            if shipment_events.last.name.downcase == 'delivered'
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end
          
        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
          :xml => response,
          :request => last_request,
          :shipment_events => shipment_events,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number)
      end
      
      def location_from_address_node(address)
        return nil unless address
        Location.new(
                :country =>     node_text_or_nil(address.elements['CountryCode']),
                :postal_code => node_text_or_nil(address.elements['PostalCode']),
                :province =>    node_text_or_nil(address.elements['StateProvinceCode']),
                :city =>        node_text_or_nil(address.elements['City']),
                :address1 =>    node_text_or_nil(address.elements['AddressLine1']),
                :address2 =>    node_text_or_nil(address.elements['AddressLine2']),
                :address3 =>    node_text_or_nil(address.elements['AddressLine3'])
              )
      end
      
      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end
      
      def response_message(xml)
        xml.get_text('/*/Response/ResponseStatusDescription | /*/Response/Error/ErrorDescription').to_s
      end
      
      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end
      
      
      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)
        
        name = case origin
        when "CA": CANADA_ORIGIN_SERVICES[code]
        when "MX": MEXICO_ORIGIN_SERVICES[code]
        when *EU_COUNTRY_CODES: EU_ORIGIN_SERVICES[code]
        end
        
        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end

      ### NEW

      def build_shipment_confirm_request(shipment)
        xml = Builder::XmlMarkup.new
        xml.instruct!
        xml.ShipmentConfirmRequest do
          xml.Request do
            xml.RequestAction 'ShipConfirm'
            xml.RequestOption 'validate'
            if shipment.number
              xml.TransactionReference do
                xml.CustomerContext shipment.number
              end
            end
          end
          xml.LabelSpecification do
            xml.LabelPrintMethod { xml.Code 'GIF' }
            xml.LabelImageFormat { xml.Code 'GIF' }
          end
          xml.Shipment do
            add_location_element(xml, 'Shipper', shipment.shipper)
            add_location_element(xml, 'ShipTo', shipment.destination)
            add_location_element(xml, 'ShipFrom', shipment.origin)
            xml.PaymentInformation do
              xml.Prepaid do
                xml.BillShipper do
                  xml.AccountNumber shipment.payer.number
                end
              end
            end
            xml.Service { xml.Code shipment.service }
            shipment.packages.each do |package|
              add_package_element(xml, package, shipment.origin)
            end
          end
        end
        xml.target!
      end

      def build_shipment_accept_request(shipment)
        xml = Builder::XmlMarkup.new
        xml.instruct!
        xml.ShipmentAcceptRequest do
          xml.Request do
            xml.RequestAction 'ShipAccept'
            if shipment.number
              xml.TransactionReference do
                xml.CustomerContext shipment.number
              end
            end
          end
          xml.ShipmentDigest shipment[:digest]
        end
        xml.target!
      end

      def add_package_element(xml, package, origin)
        raise package.class.to_s unless package.kind_of?(ActiveMerchant::Shipping::Package)
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
        xml.Package do
          xml.PackagingType { xml.Code '02' }
          unless package.description.blank?
            xml.Description package.description
          end
          axes = [:length, :width, :height]
          values = axes.map do |axis|
            if imperial
              package.inches(axis)
            else
              package.cm(axis)
            end
          end
          if values.all? {|v| v > 0 }
            xml.Dimensions do
              xml.UnitOfMeasurement do
                xml.Code(imperial ? 'IN' : 'CM')
              end
              axes.each_with_index do |axis, i|
                value = (values[i].to_f * 1000).round / 1000.0
                xml.tag!(axis.to_s.capitalize, [values[i], 0.1].max.to_s)
              end
            end
          end
          xml.PackageWeight do
            xml.UnitOfMeasurement do
              xml.Code(imperial ? 'LBS' : 'KGS')
            end
            value = (imperial ? package.lbs : package.kgs)
            value = (value.to_f * 1000).round / 1000.0 # 3 decimals
            xml.Weight [value, 0.1].max.to_s
          end
          # not implemented:  * Shipment/Package/LargePackageIndicator element
          #                   * Shipment/Package/ReferenceNumber element
          #                   * Shipment/Package/PackageServiceOptions element
          #                   * Shipment/Package/AdditionalHandling element  
        end
      end

      def add_location_element(xml, name, object)
        xml.tag!(name) do
          node_name = (name == 'Shipper' ? 'Name' : 'CompanyName')
          xml.tag!(node_name, object.name)
          if node_name == 'CompanyName' && !object.attention.blank?
            xml.AttentionName object.attention
          end
          unless object.phone.blank?
            xml.PhoneNumber object.phone.gsub(/[^\d]/, '') 
          end
          unless object.fax.blank?
            xml.FaxNumber object.phone.gsub(/[^\d]/, '') 
          end
          if name == 'Shipper'
            xml.ShipperNumber object.number
          elsif name == 'ShipTo' && object.respond_to?(:number) && !object.number.blank?
            xml.ShipperAssignedIdentificationNumber object.number
          end
          xml.Address do
            values = [
              [object.address1, :AddressLine1],
              [object.address2, :AddressLine2],
              [object.address3, :AddressLine3],
              [object.city, :City],
              [object.province, :StateProvinceCode],
              [object.postal_code, :PostalCode],
              [object.country_code(:alpha2), :CountryCode],
              [!object.commercial?, :ResidentialAddressIndicator]
            ]
            values.select {|v, n| v && v != '' }.each do |v, n|
              xml.tag!(n, v)
            end
          end
        end
      end
      
      def parse_money(element)
        value = element.elements['MonetaryValue'].text
        currency = element.elements['CurrencyCode'].text
        Money.new((BigDecimal(value) * 100).to_i, currency)
      end

      def parse_shipment_confirm(shipment, response)
        xml = REXML::Document.new(response)
        if response_success?(xml)
          confirm_response = xml.elements['/ShipmentConfirmResponse']
          shipment.price = parse_money(confirm_response.elements['ShipmentCharges/TotalCharges'])
          shipment[:digest] = confirm_response.text('ShipmentDigest')
        else
          shipment.errors = response_message(xml)
        end
        shipment
      end

      def parse_shipment_accept(shipment, response)
        xml = REXML::Document.new(response)
        shipment_results = xml.elements['/ShipmentAcceptResponse/ShipmentResults']
        shipment.price = parse_money(shipment_results.elements['ShipmentCharges/TotalCharges'])
        shipment.tracking = shipment_results.elements['ShipmentIdentificationNumber'].text
        shipment.labels = []
        shipment_results.elements.each('PackageResults') do |package_results|
          shipment.labels << Label.new(
            :tracking => package_results.text('TrackingNumber'),
            :image => Base64.decode64(package_results.text('LabelImage/GraphicImage'))
          )
        end
        shipment
      end
    end
  end
end
