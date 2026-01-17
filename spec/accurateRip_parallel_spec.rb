require 'rubyripper/accurateRip'
require 'parallel'

describe AccurateRipResult do
  describe '#merge' do
    it 'should merge results from another instance' do
      result1 = AccurateRipResult.new
      result1.setComputedChecksums(1, 0x111, 0x222)
      result1.setTrackResult(1, true, :v1, 0, 10)

      result2 = AccurateRipResult.new
      result2.setComputedChecksums(2, 0x333, 0x444)
      result2.setTrackResult(2, false, nil, nil, nil)

      result1.merge(result2)

      expect(result1.computed_v1[1]).to eq(0x111)
      expect(result1.computed_v2[1]).to eq(0x222)
      expect(result1.track_results[1][:matched]).to eq(true)

      expect(result1.computed_v1[2]).to eq(0x333)
      expect(result1.computed_v2[2]).to eq(0x444)
      expect(result1.track_results[2][:matched]).to eq(false)
    end
  end
end

describe AccurateRip do
  let(:disc) { double('Disc').as_null_object }
  let(:prefs) { double('Preferences').as_null_object }
  let(:ar) { AccurateRip.new(disc, prefs) }

  before do
    allow(Parallel).to receive(:processor_count).and_return(2)
    # Silence stdout
    allow($stdout).to receive(:write)
  end

  describe '#verifyTracks' do
    it 'should use Parallel.map with in_processes' do
      files = { 1 => 'track1.wav', 2 => 'track2.wav' }
      
      expect(Parallel).to receive(:map).with(files, hash_including(in_processes: 2)).and_call_original

      # Mock reading audio data to avoid FS error and actually return verification
      allow(ar).to receive(:readAudioData).and_return('dummy_audio_data')
      # Mock prepareVerification to avoid net request
      allow(ar).to receive(:prepareVerification)
      
      # Mock verifyTrackData to prevent errors
      allow(ar).to receive(:verifyTrackData)

      # We need to stub Parallel.map's block execution because rspec mock kills the yield if not careful? 
      # Actually and_call_original executes it. 
      # But inside the block, it creates new AccurateRipResult and calls methods.
      # The block runs in a FORKED process. RSpec mocks might not carry over to forks easily.
      # However, Parallel.map runs the block.
      
      # For simple verification that Parallel is called:
      ar.verifyTracks(files)
    end
  end

  describe '#verifyImage' do
    it 'should use Parallel.map with in_processes' do
      file_path = 'image.wav'
      allow(disc).to receive(:audiotracks).and_return(2)
      
      expect(Parallel).to receive(:map).with(1..2, hash_including(in_processes: 2)).and_call_original

      allow(ar).to receive(:readAudioData).and_return('dummy_large_audio_data')
      allow(ar).to receive(:prepareVerification)
      allow(ar).to receive(:extractTrackFromImage).and_return('dummy_track_data')
      allow(ar).to receive(:verifyTrackData)

      ar.verifyImage(file_path)
    end
  end
end
