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

require 'net/http'
require 'uri'
require 'tempfile'
require 'rubyripper/modules/audioCalculations'
require 'rubyripper/preferences/main'

# Class to hold the verification results of AccurateRip
class AccurateRipResult
  include AudioCalculations

  attr_reader :status,           # true if all tracks matched
              :computed_v1,      # {track_number => crc}
              :computed_v2,      # {track_number => crc}
              :pressings,        # Array of multiple pressing data
              :track_results     # {track_number => {matched: bool, version: :v1/:v2, pressing_index: int, confidence: int}}

  def initialize
    @status = false
    @computed_v1 = {}
    @computed_v2 = {}
    @pressings = []
    @track_results = {}
  end

  # Set CRC calculated locally
  def setComputedChecksums(track, v1_crc, v2_crc)
    @computed_v1[track] = v1_crc
    @computed_v2[track] = v2_crc
  end

  # Add remote pressing data
  def addPressing(pressing_data)
    @pressings << pressing_data
  end

  # Set verification result per track
  def setTrackResult(track, matched, version, pressing_index, confidence)
    @track_results[track] = {
      matched: matched,
      version: version,
      pressing_index: pressing_index,
      confidence: confidence
    }
  end

  # Check if all tracks matched
  def finalize
    @status = @track_results.values.all? { |r| r[:matched] }
  end

  # Generate string for logging (table format)
  def toStr
    lines = []
    lines << "AccurateRip verification results:"

    if @pressings.empty?
      lines << "  No entry found in the database"
      return lines.join("\n")
    end

    lines << "  #{@pressings.size} pressing(s) found in the database"
    lines << ""

    # Table header
    lines << "     Track |  V1 CRC  |  V2 CRC  |   Result   | DB"
    lines << "    -------+----------+----------+------------+------------------------------------------"

    # Track results
    @computed_v1.keys.sort.each do |track|
      result = @track_results[track]
      v1_crc = format('%08X', @computed_v1[track])
      v2_crc = format('%08X', @computed_v2[track])

      # Result column
      if result && result[:matched]
        result_str = "Matched"
      else
        result_str = "Unmatched"
      end

      # DB column: list CRCs and confidence for all pressings
      db_entries = []
      @pressings.each do |pressing|
        track_data = pressing[:tracks][track]
        if track_data && track_data[:crc] != 0
          crc_str = format('%08X', track_data[:crc])
          db_entries << "#{crc_str}(#{track_data[:confidence]})"
        end
      end
      db_str = db_entries.empty? ? "-" : db_entries.join(", ")

      lines << format("       %2d  | %s | %s | %9s  | %s", 
                      track, v1_crc, v2_crc, result_str, db_str)
    end

    lines << ""
    lines << " #{@status ? 'All tracks verified successfully' : 'Some tracks did not match'}"

    lines.join("\n")
  end
end

# Class to perform CD verification using AccurateRip
class AccurateRip
  include AudioCalculations

  SECTOR_BYTES = 2352
  SKIP_SECTORS = 5

  def initialize(disc, prefs = nil)
    @disc = disc
    @prefs = prefs || Preferences::Main.instance
    @disc_ident = nil
  end

  # Verify multiple tracks and return AccurateRipResult (track mode)
  # files: hash map of {track_number => file_path}
  def verifyTracks(files)
    result = AccurateRipResult.new
    prepareVerification(result)

    files.each do |track, file_path|
      audio_data = readAudioData(file_path)
      next unless audio_data
      verifyTrackData(track, audio_data, result)
    end

    result.finalize
    result
  end

  # Verify image file and return AccurateRipResult (image mode)
  # file_path: path to the image file
  def verifyImage(file_path)
    result = AccurateRipResult.new
    prepareVerification(result)

    audio_data = readAudioData(file_path)
    return result unless audio_data

    track_count = @disc.audiotracks
    (1..track_count).each do |track|
      track_audio_data = extractTrackFromImage(audio_data, track)
      next unless track_audio_data
      verifyTrackData(track, track_audio_data, result)
    end

    result.finalize
    result
  end

  private

  # Prepare for verification (build Disc Ident and fetch database)
  def prepareVerification(result)
    buildDiscIdent

    bin_path = fetchAccurateRipFile
    if bin_path
      parseAccurateRipData(bin_path, result)
      File.delete(bin_path) if File.exist?(bin_path)
    end
  end

  # Verify audio data of a single track
  def verifyTrackData(track, audio_data, result)
    v1_crc = computeV1Checksum(track, audio_data)
    v2_crc = computeV2Checksum(track, audio_data)

    result.setComputedChecksums(track, v1_crc, v2_crc)
    matchTrackWithPressings(track, v1_crc, v2_crc, result)
  end

  # Compare track with pressing data
  def matchTrackWithPressings(track, v1_crc, v2_crc, result)
    matched = false
    result.pressings.each_with_index do |pressing, idx|
      track_data = pressing[:tracks][track]
      next unless track_data

      if track_data[:crc] == v2_crc
        result.setTrackResult(track, true, :v2, idx, track_data[:confidence])
        matched = true
        break
      elsif track_data[:crc] == v1_crc
        result.setTrackResult(track, true, :v1, idx, track_data[:confidence])
        matched = true
        break
      end
    end

    result.setTrackResult(track, false, nil, nil, nil) unless matched
  end

  # Extract audio data of a specific track from the image file
  def extractTrackFromImage(image_audio_data, track)
    # Get start sector and length of the track
    # Calculate relative position within the image (relative to track 1)
    first_track_start = @disc.getStartSector(1)
    track_start = @disc.getStartSector(track)
    track_length = @disc.getLengthSector(track)

    # Byte offset within the image
    relative_start = track_start - first_track_start
    byte_offset = relative_start * SECTOR_BYTES
    byte_length = track_length * SECTOR_BYTES

    # Range check
    return nil if byte_offset < 0
    return nil if byte_offset + byte_length > image_audio_data.size

    # Extract data
    image_audio_data[byte_offset, byte_length]
  end

  # Build Disc Identifier
  def buildDiscIdent
    track_count = @disc.audiotracks
    track_offsets_added = 0
    track_offsets_multiplied = 0

    # Collect start LBA of each track
    offsets = []
    (1..track_count).each do |track|
      lba = @disc.getStartSector(track)
      offsets << lba
      track_offsets_added += lba
      lba = 1 if lba == 0  # Calculate as 1 if it is 0
      track_offsets_multiplied += lba * track
    end

    # Also add end position of the last track
    last_track_end = @disc.getStartSector(track_count) + @disc.getLengthSector(track_count)
    offsets << last_track_end
    track_offsets_added += last_track_end
    last_track_end = 1 if last_track_end == 0
    track_offsets_multiplied += last_track_end * (track_count + 1)

    # Get FreeDB ID
    freedb_id = @disc.freedbDiscid.to_i(16) rescue 0

    @disc_ident = {
      track_count: track_count,
      track_offsets_added: track_offsets_added & 0xFFFFFFFF,
      track_offsets_multiplied: track_offsets_multiplied & 0xFFFFFFFF,
      freedb_id: freedb_id & 0xFFFFFFFF
    }
  end

  # Download bin file from AccurateRip database
  def fetchAccurateRipFile
    return nil unless @disc_ident

    track_offsets_added_hex = format('%08x', @disc_ident[:track_offsets_added])
    url_path = "/accuraterip/#{track_offsets_added_hex[7]}/#{track_offsets_added_hex[6]}/#{track_offsets_added_hex[5]}/" \
               "dBAR-#{format('%03d', @disc_ident[:track_count])}-" \
               "#{format('%08x', @disc_ident[:track_offsets_added])}-" \
               "#{format('%08x', @disc_ident[:track_offsets_multiplied])}-" \
               "#{format('%08x', @disc_ident[:freedb_id])}.bin"

    uri = URI.parse("http://www.accuraterip.com#{url_path}")

    begin
      response = Net::HTTP.get_response(uri)
      if response.code == '200'
        temp_file = Tempfile.new(['accuraterip', '.bin'])
        temp_file.binmode
        temp_file.write(response.body)
        temp_file.close
        return temp_file.path
      else
        puts "AccurateRip: Could not get data from database (HTTP #{response.code})" if @prefs.debug
        return nil
      end
    rescue StandardError => e
      puts "AccurateRip: Network error: #{e.message}" if @prefs.debug
      return nil
    end
  end

  # Parse bin file and add pressing data to result
  # Structure:
  #   STAcRipDiscIdent (13 bytes):
  #     - TrackCount: 1 byte
  #     - TrackOffsetsAdded: 4 bytes (little endian)
  #     - TrackOffsetsMultiplied: 4 bytes (little endian)
  #     - FreedBIdent: 4 bytes (little endian)
  #   STAcRipATrack (9 bytes x track_count):
  #     - Confidence: 1 byte
  #     - TrackCRC: 4 bytes (little endian)
  #     - OffsetFindCRC: 4 bytes (little endian)
  def parseAccurateRipData(file_path, result)
    File.open(file_path, 'rb') do |f|
      until f.eof?
        # Load DiscIdent (13 bytes)
        ident_data = f.read(13)
        break if ident_data.nil? || ident_data.size < 13

        track_count = ident_data[0].ord
        # track_offsets_added = ident_data[1..4].unpack1('V')
        # track_offsets_multiplied = ident_data[5..8].unpack1('V')
        # freedb_id = ident_data[9..12].unpack1('V')

        pressing = { tracks: {} }

        # Load data of each track (9 bytes x track_count)
        track_count.times do |i|
          track_data = f.read(9)
          break if track_data.nil? || track_data.size < 9

          confidence = track_data[0].ord
          track_crc = track_data[1..4].unpack1('V')
          # offset_find_crc = track_data[5..8].unpack1('V')  # Not used

          pressing[:tracks][i + 1] = {
            confidence: confidence,
            crc: track_crc
          }
        end

        result.addPressing(pressing)
      end
    end
  end

  # Load audio data from WAV file
  def readAudioData(file_path)
    return nil unless File.exist?(file_path)

    File.open(file_path, 'rb') do |f|
      f.seek(BYTES_WAV_CONTAINER)  # Skip WAV header
      f.read
    end
  end

  # Calculate AccurateRip V1 CRC
  def computeV1Checksum(track, audio_data)
    data_size = audio_data.size
    dword_count = data_size / 4

    # Calculate skip range
    skip_from = 0
    skip_to = dword_count

    # Skip the first 5 sectors of the first track
    if track == 1
      skip_from = (SECTOR_BYTES * SKIP_SECTORS) / 4
    end

    # Skip the last 5 sectors of the last track
    if track == @disc.audiotracks
      skip_to -= (SECTOR_BYTES * SKIP_SECTORS) / 4
    end

    crc = 0
    pos = 1

    dword_count.times do |i|
      if pos >= skip_from && pos <= skip_to
        # Load 4 bytes as little endian
        sample = audio_data[i * 4, 4].unpack1('V')
        crc += pos * sample
        crc &= 0xFFFFFFFF  # Limit to 32bit
      end
      pos += 1
    end

    crc
  end

  # Calculate AccurateRip V2 CRC
  def computeV2Checksum(track, audio_data)
    data_size = audio_data.size
    dword_count = data_size / 4

    # Calculate skip range
    skip_from = 0
    skip_to = dword_count

    # Skip the first 5 sectors of the first track
    if track == 1
      skip_from = (SECTOR_BYTES * SKIP_SECTORS) / 4
    end

    # Skip the last 5 sectors of the last track
    if track == @disc.audiotracks
      skip_to -= (SECTOR_BYTES * SKIP_SECTORS) / 4
    end

    crc = 0
    pos = 1

    dword_count.times do |i|
      if pos >= skip_from && pos <= skip_to
        sample = audio_data[i * 4, 4].unpack1('V')

        # V2: multiply 64bit and add HI/LO
        calc = pos * sample
        lo = calc & 0xFFFFFFFF
        hi = (calc >> 32) & 0xFFFFFFFF

        crc += hi + lo
        crc &= 0xFFFFFFFF
      end
      pos += 1
    end

    crc
  end
end
