#!/usr/bin/env ruby
#    Rubyripper - A secure ripper for Linux/BSD/OSX
#    Copyright (C) 2007 - 2010  Bouke Woudstra (boukewoudstra@gmail.com)
#
#    This file is part of Rubyripper. Rubyripper is free software: you can
#    redistribute it and/or modify it under the terms of the GNU General
#    Public License as published by the Free Software Foundation, either
#    version 3 of the License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

require 'rexml/document'
require 'tempfile'
require 'rubyripper/preferences/main'
require 'rubyripper/system/execute'
require 'rubyripper/disc/cuesheet'
require 'shellwords'

# Class to hold the verification results of CTDB
class CtdbResult
  attr_reader :status,         # status string from ctdb-cli (e.g., 'found', 'not_found', 'failure')
              :confidence,     # confidence value from database
              :message,        # additional message from ctdb-cli
              :entries         # array of database entries

  def initialize
    @status = nil
    @confidence = 0
    @message = nil
    @entries = []
  end

  # Parse XML output from ctdb-cli verify command
  def parseXml(xml_string)
    return if xml_string.nil? || xml_string.empty?

    begin
      doc = REXML::Document.new(xml_string)
      verify_element = doc.elements['ctdb/verify_result']
      return unless verify_element

      @status = verify_element.attributes['status']
      @message = verify_element.attributes['message']
      @confidence = verify_element.attributes['confidence'].to_i

      # Parse entries
      verify_element.elements.each('entry') do |entry|
        entry_data = {
          conf: entry.attributes['conf'].to_i,
          crc: entry.attributes['crc'],
          status: entry.attributes['status']
        }
        @entries << entry_data
      end
    rescue REXML::ParseException => e
      @message = "XML parse error: #{e.message}"
      @status = 'failure'
    end
  end

  # Check if database entry was found (regardless of match result)
  def entryFound?
    !@entries.empty? || @status == 'found'
  end

  # Generate string for logging
  def toStr
    lines = []
    lines << "CTDB verification results:"

    if @status == 'not_found' || @entries.empty?
      lines << "  No entry found in the database"
      return lines.join("\n")
    end

    lines << "  Status: #{@status}"
    lines << "  Confidence: #{@confidence}" if @confidence > 0
    lines << "  Message: #{@message}" if @message && !@message.empty?

    unless @entries.empty?
      lines << ""
      lines << "  Database entries:"
      @entries.each_with_index do |entry, idx|
        lines << "    #{idx + 1}. Confidence: #{entry[:conf]}, CRC: #{entry[:crc]}, Status: #{entry[:status]}"
      end
    end

    lines << ""
    lines << "  #{@status == 'found' ? 'Verification successful' : 'Verification failed'}"

    lines.join("\n")
  end
end

# Class to perform CD verification using CTDB (CUETools Database)
# This class follows the same pattern as AccurateRip class
class Ctdb
  def initialize(disc, cdrdao, fileScheme, prefs = nil, deps = nil, exec = nil)
    @disc = disc
    @cdrdao = cdrdao
    @fileScheme = fileScheme
    @prefs = prefs || Preferences::Main.instance
    @deps = deps || Dependency.instance
    @exec = exec || Execute.new
  end

  # Verify image file and return CtdbResult
  # file_path: path to the WAV image file
  def verifyImage(file_path)
    result = CtdbResult.new

    # Check if ctdb-cli is installed
    unless @deps.installed?('ctdb-cli')
      result.instance_variable_set(:@message, "ctdb-cli not installed")
      return result
    end

    return result unless File.exist?(file_path)

    # Generate temporary CUE sheet pointing to the image file
    temp_cue = generateTempCue(file_path)
    return result unless temp_cue

    begin
      # Execute ctdb-cli verify command
      xml_output = executeVerify(temp_cue.path)
      result.parseXml(xml_output)
    ensure
      # Clean up temporary CUE file
      temp_cue.close
      temp_cue.unlink
    end

    result
  end

  private

  # Generate a temporary CUE sheet pointing to the specified WAV file
  def generateTempCue(wav_path)
    # Create a cuesheet that references the temporary WAV file
    cuesheet = Cuesheet.new(@disc, @cdrdao, @fileScheme, nil, @prefs, @deps)
    cue_content = cuesheet.save('wav', wav_path)

    # Create the temp CUE in the same directory as the wav_path provided.
    dir = File.dirname(wav_path)
    temp_cue = Tempfile.new(['ctdb_verify', '.cue'], dir)
    temp_cue.write(cue_content.join("\n"))
    temp_cue.flush

    temp_cue
  rescue StandardError => e
    puts "CTDB: Error generating temp CUE: #{e.message}" if @prefs.debug
    nil
  end

  # Execute ctdb-cli verify command and return XML output
  def executeVerify(cue_path)
    command = "ctdb-cli --xml verify #{Shellwords.escape(cue_path)}"
    stdout_str, stderr_str, status = Open3.capture3(command)
    puts "CTDB stderr: #{stderr_str}" if @prefs.debug && !stderr_str.empty?
    stdout_str

  rescue StandardError => e
    puts "CTDB: Error executing ctdb-cli: #{e.message}" if @prefs.debug
    nil
  end
end
