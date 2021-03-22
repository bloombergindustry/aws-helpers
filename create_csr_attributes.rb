#!/opt/puppetlabs/puppet/bin/ruby

require "net/http"
require 'json'
require "uri"
require 'fileutils'

begin

  uri = URI.parse("http://169.254.169.254")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 4
  http.read_timeout = 4
  request = Net::HTTP::Get.new("/latest/meta-data/instance-id")
  response = http.request(request)
  instance_id = response.body

rescue

  STDERR.puts "This is not an AWS EC2 instance or unable to contact the AWS instance-data web server.\n"

end

if !instance_id.is_a? String then

  STDERR.puts "instance_id is not a string\n"

else

  request2 = Net::HTTP::Get.new("/latest/meta-data/placement/availability-zone")
  response2 = http.request(request2)
  r = response2.body
  region = /.*-.*-[0-9]/.match(r)

  begin

    # Some edge cases may require multiple attempts to re-run 'aws ec2 describe-tags' due to API rate limits
    # Making up to 6 attempts with sleep time ranging between 4-10 seconds after each unsuccessful attempt
    for i in 1..6
      jsonString = `aws ec2 describe-tags --filters "Name=resource-id,Values=#{instance_id}" --region #{region} --output json`
      break if jsonString != ''
      sleep rand(4..10)
    end

    # convert json string to hash
    hash = JSON.parse(jsonString)

    if hash.is_a? Hash then

      if hash.has_key?("Tags") then
        result = {}
        hash['Tags'].each do |child|
          name = child['Key'].to_s
          if name.start_with?("ec2:pp_") then
            # strip ec2: prefix from tags
            name.sub!(/^ec2:/,'')
            name.gsub!(/\W/,'_')
            # append to the hash for structured tags
            result[name] = child['Value']
          else
            next
          end
        end

        unless result.empty? then
          begin
            FileUtils.mkdir_p('/etc/puppetlabs/puppet')
            csr_attributes = File.new("/etc/puppetlabs/puppet/csr_attributes.yaml", "w")
            csr_attributes.write("---\nextension_requests:\n")
            result.each do |k,v|
              csr_attributes.write("  #{k}: '#{v}'\n")
            end

          rescue

            STDERR.puts "Couldn't create /etc/puppetlabs/puppet/csr_attributes.yaml\n"

          ensure

            csr_attributes.close unless csr_attributes.nil?

          end
        else
          STDERR.puts "No puppet tags have been found\n"
        end
      else
       STDERR.puts "No tags have been found\n"
      end
    end

  rescue

    STDERR.puts "awscli exec failed\n"

  end
end
