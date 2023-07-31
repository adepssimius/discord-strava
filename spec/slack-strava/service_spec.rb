require 'spec_helper'

describe DiscordStrava::Service do
  context '#url' do
    before do
      @rack_env = ENV.fetch('RACK_ENV', nil)
    end
    after do
      ENV['RACK_ENV'] = @rack_env
    end
    it 'defaults to playplay.io in production' do
      expect(DiscordStrava::Service.url).to eq 'https://strada.playplay.io'
    end
    context 'in development' do
      before do
        ENV['RACK_ENV'] = 'development'
      end
      it 'defaults to localhost' do
        expect(DiscordStrava::Service.url).to eq 'http://localhost:5000'
      end
    end
    context 'when set' do
      before do
        ENV['URL'] = 'updated'
      end
      after do
        ENV.delete('URL')
      end
      it 'defaults to ENV' do
        expect(DiscordStrava::Service.url).to eq 'updated'
      end
    end
  end
end
