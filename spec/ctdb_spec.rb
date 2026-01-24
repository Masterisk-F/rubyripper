#!/usr/bin/env ruby
#    Rubyripper - A secure ripper for Linux/BSD/OSX
#    Copyright (C) 2007 - 2010 Bouke Woudstra (boukewoudstra@gmail.com)
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

require 'rubyripper/ctdb'

describe CtdbResult do
  let(:result) { CtdbResult.new }

  describe '#initialize' do
    it 'should initialize status as false' do
      expect(result.status).to be false
    end

    it 'should initialize confidence as 0' do
      expect(result.confidence).to eq(0)
    end

    it 'should initialize total_entries as 0' do
      expect(result.total_entries).to eq(0)
    end

    it 'should initialize entries as an empty array' do
      expect(result.entries).to eq([])
    end
  end

  describe '#parseXml' do
    context 'status determination tests' do
      it 'should set status to true if confidence is 2 or more' do
        xml = <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="2" total_entries="10"/>
          </ctdb>
        XML
        result.parseXml(xml)
        expect(result.status).to be true
      end

      it 'should set status to true if confidence is 1 and total_entries is 1' do
        xml = <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="1" total_entries="1"/>
          </ctdb>
        XML
        result.parseXml(xml)
        expect(result.status).to be true
      end

      it 'should set status to false if confidence is 1 and total_entries is 2 or more' do
        xml = <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="1" total_entries="2"/>
          </ctdb>
        XML
        result.parseXml(xml)
        expect(result.status).to be false
      end

      it 'should set status to false if confidence is 0' do
        xml = <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="0" total_entries="10"/>
          </ctdb>
        XML
        result.parseXml(xml)
        expect(result.status).to be false
      end
    end

    context 'successful parsing' do
      let(:xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result toc="12345" status="found" confidence="10" total_entries="2">
              <entry id="1" conf="8" crc="ABCD1234" offset="0" status="verified" has_errors="false" can_recover="false">
                <track number="1" local_crc="1111" remote_crc="1111" matched="true"/>
              </entry>
              <entry id="2" conf="5" crc="EFGH5678" offset="0" status="verified" has_errors="false" can_recover="false"/>
            </verify_result>
          </ctdb>
        XML
      end

      before { result.parseXml(xml) }

      it 'should set status to true' do
        expect(result.status).to be true
      end

      it 'should set confidence to 10' do
        expect(result.confidence).to eq(10)
      end

      it 'should set total_entries to 2' do
        expect(result.total_entries).to eq(2)
      end

      it 'should have 2 entries' do
        expect(result.entries.size).to eq(2)
      end

      it 'should return true for #entryFound?' do
        expect(result.entryFound?).to be true
      end
    end

    context 'when status is failure' do
      let(:xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result status="failure" message="Audio file not found."/>
          </ctdb>
        XML
      end

      before { result.parseXml(xml) }

      it 'should set status to false' do
        expect(result.status).to be false
      end

      it 'should set message to the error message' do
        expect(result.message).to eq('Audio file not found.')
      end
    end

    context 'when XML parsing fails' do
      let(:invalid_xml) { '<invalid><xml>' }

      before { result.parseXml(invalid_xml) }

      it 'should set status to false' do
        expect(result.status).to be false
      end

      it 'should include error information in message' do
        expect(result.message).to include('XML parse error')
      end
    end
  end

  describe '#toStr' do
    context 'when successful' do
      let(:xml) do
        <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="2" total_entries="1">
              <entry id="1" conf="2" crc="ABCD" status="verified"/>
            </verify_result>
          </ctdb>
        XML
      end

      before { result.parseXml(xml) }

      it 'should include "Verification successful"' do
        expect(result.toStr).to include('Verification successful')
      end

      it 'should include "Confidence: 2"' do
        expect(result.toStr).to include('Confidence: 2')
      end
    end

    context 'when not found' do
      let(:xml) do
        <<~XML
          <ctdb xmlns="http://db.cuetools.net/ns/mmd-1.0#">
            <verify_result confidence="0" total_entries="0"/>
          </ctdb>
        XML
      end

      before { result.parseXml(xml) }

      it 'should include "No entry found"' do
        expect(result.toStr).to include('No entry found in the database')
      end
    end
  end
end
