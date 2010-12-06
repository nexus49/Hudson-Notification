require 'net/http'
require 'uri'
require 'rexml/document'

module HudsonMonitor

  class Job  < Struct.new(:name, :success, :last_build_number, :age, :last_success_number, :last_failure_number); end
  
  class HudsonDao
    attr_accessor :first_level_notification, :second_level_notification, :thir_level_notification
    
    def initialize
      hudson_url = "http://10.201.55.38:8080/hudson/"
      @api_url = "api/xml"
      @url = URI.parse("#{hudson_url}#{@api_url}")
      @first_level_notification = 5
      @second_level_notification = 25
      @thir_level_notification = 50
    end

    def get_current_job_state
      resp = Net::HTTP.get_response(@url)
      xml = resp.body
      hash = {}
      doc, posts = REXML::Document.new(xml), []
      doc.elements.each('hudson/job') do |p|
        hash[p.elements['name'].text] = get_job p 
      end 
      hash
    end      

    def get_job(xml_job)
      url = xml_job.elements['url'].text

      api_uri = URI.parse("#{url}#{@api_url}")
      job_resp = Net::HTTP.get_response(api_uri)      
      job_doc = REXML::Document.new(job_resp.body)
      job_root = job_doc.elements['freeStyleProject']
      
      last_build_url= job_root.elements['lastBuild'].elements['url'].text
      last_build_uri = URI.parse("#{last_build_url}#{@api_url}")
      last_build_resp = Net::HTTP.get_response(last_build_uri)  
      
      last_build_doc = REXML::Document.new(last_build_resp.body)
      last_build_root = last_build_doc.elements['freeStyleBuild']

      name = xml_job.elements['name'].text
      last_build_number = last_build_root.elements['number'].text
      success = last_build_root.elements['result'].text == "SUCCESS" unless last_build_root.elements['result'].nil?

      age = 0
      last_failed_number = 0
      last_stable_number = 0
      
      if success 
        last_failed_build = job_root.elements['lastFailedBuild']
        last_failed_number = last_failed_build.nil? ? 0: last_failed_build.elements['number'].text
        age = last_build_number.to_i - last_failed_number.to_i  
        last_stable_number = last_build_number
      else
        last_stable_build = job_root.elements['lastStableBuild']
        last_stable_number = last_stable_build.nil? ? 0: last_stable_build.elements['number'].text
        age = last_build_number.to_i - last_stable_number.to_i
        last_failed_number = last_build_number
      end
      
      Job.new(name, success, last_build_number, age, last_stable_number,last_failed_number)
    end     
  end
  
end

def run
  dao = HudsonMonitor::HudsonDao.new
  last_jobs = dao.get_current_job_state

  puts "Init done."
  while(true)
    sleep 10
    current_jobs = dao.get_current_job_state

    current_jobs.each do |key, job|
      if last_jobs.has_key? key
        if(job.last_build_number != last_jobs[key].last_build_number)
            system "say '#{key} failed for the #{job.age} time.'" if(last_jobs[key].success == true && job.success == false)
            system "say '#{key} does not fail anymore.'" if(last_jobs[key].success == false && !job.success == true)
        
          if(job.success == false)
            if(job.age == dao.first_level_notification)
              puts "level 1"
            elseif(job.age == dao.second_level_notification)
              puts "level 2"
            elseif(job.age == dao.third_level_notification)
              puts "level 3"
            end
          end
        end
      else
        system "say '#{key} failed for the first time.'" unless job.success == true
      end
    end
    last_jobs = current_jobs
    puts "Check done."
  end
end

run