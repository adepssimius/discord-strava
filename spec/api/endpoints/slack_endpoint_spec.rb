require 'spec_helper'

describe Api::Endpoints::DiscordEndpoint do
  include Api::Test::EndpointTest

  context 'with a SLACK_VERIFICATION_TOKEN' do
    let(:token) { 'discord-verification-token' }
    let(:team) { Fabricate(:team) }
    before do
      ENV['SLACK_VERIFICATION_TOKEN'] = token
    end
    context 'interactive buttons' do
      let(:user) { Fabricate(:user, team: team, access_token: 'token', token_expires_at: Time.now + 1.day) }
      context 'without a club' do
        let(:club) do
          Club.new(
            name: 'Orchard Street Runners',
            description: 'www.orchardstreetrunners.com',
            url: 'OrchardStreetRunners',
            city: 'New York',
            state: 'New York',
            country: 'United States',
            member_count: 146,
            logo: 'https://dgalywyr863hv.cloudfront.net/pictures/clubs/43749/1121181/4/medium.jpg'
          )
        end
        it 'connects club', vcr: { cassette_name: 'strava/retrieve_a_club' } do
          expect {
            expect_any_instance_of(Discord::Web::Client).to receive(:chat_postMessage).with(
              club.to_discord.merge(
                as_user: true,
                channel: 'C12345',
                text: "A club has been connected by #{user.discord_mention}."
              )
            )
            expect_any_instance_of(Strava::Api::Client).to receive(:paginate)
            expect_any_instance_of(Club).to receive(:sync_last_strava_activity!)
            post '/api/discord/action', payload: {
              actions: [{ name: 'strava_id', value: '43749' }],
              channel: { id: 'C12345', name: 'runs' },
              user: { id: user.user_id },
              team: { id: team.guild_id },
              token: token,
              callback_id: 'club-connect-channel'
            }.to_json
            expect(last_response.status).to eq 201
            response = JSON.parse(last_response.body)
            expect(response['attachments'][0]['actions'][0]['text']).to eq 'Disconnect'
          }.to change(Club, :count).by(1)
        end
      end
      context 'with a club' do
        let!(:club) { Fabricate(:club, team: team) }
        it 'disconnects club' do
          expect {
            expect_any_instance_of(Strava::Api::Client).to receive(:paginate)
            expect_any_instance_of(Discord::Web::Client).to receive(:chat_postMessage).with(
              club.to_discord.merge(
                as_user: true,
                channel: club.channel_id,
                text: "A club has been disconnected by #{user.discord_mention}."
              )
            )
            post '/api/discord/action', payload: {
              actions: [{ name: 'strava_id', value: club.strava_id }],
              channel: { id: club.channel_id, name: 'runs' },
              user: { id: user.user_id },
              team: { id: team.guild_id },
              token: token,
              callback_id: 'club-disconnect-channel'
            }.to_json
            expect(last_response.status).to eq 201
            response = JSON.parse(last_response.body)
            expect(response['text']).to eq('Not connected to any clubs.')
            expect(response['attachments']).to eq([])
          }.to change(Club, :count).by(-1)
        end
      end
      it 'returns an error with a non-matching verification token' do
        post '/api/discord/action', payload: {
          actions: [{ name: 'strava_id', value: '43749' }],
          channel: { id: 'C1', name: 'runs' },
          user: { id: user.user_id },
          team: { id: team.guild_id },
          callback_id: 'invalid-callback',
          token: 'invalid-token'
        }.to_json
        expect(last_response.status).to eq 401
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq 'Message token is not coming from Discord.'
      end
      it 'returns invalid callback id' do
        post '/api/discord/action', payload: {
          actions: [{ name: 'strava_id', value: 'id' }],
          channel: { id: 'C1', name: 'runs' },
          user: { id: user.user_id },
          team: { id: team.guild_id },
          callback_id: 'invalid-callback',
          token: token
        }.to_json
        expect(last_response.status).to eq 404
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq 'Callback invalid-callback is not supported.'
      end
    end
    context 'slash commands' do
      let(:user) { Fabricate(:user, team: team) }
      context 'stats' do
        it 'returns team stats' do
          post '/api/discord/command',
               command: '/strada',
               text: 'stats',
               channel_id: 'channel',
               channel_name: 'channel_name',
               user_id: user.user_id,
               guild_id: team.guild_id,
               token: token
          expect(last_response.status).to eq 201
          response = JSON.parse(last_response.body)
          expect(response).to eq(
            'text' => 'There are no activities in this channel.',
            'user' => user.user_id,
            'channel' => 'channel'
          )
        end
        it 'calls stats with channel' do
          expect_any_instance_of(Team).to receive(:stats).with(channel_id: 'channel_id')
          post '/api/discord/command',
               command: '/strada',
               text: 'stats',
               channel_id: 'channel_id',
               channel_name: 'channel_name',
               user_id: user.user_id,
               guild_id: team.guild_id,
               token: token
        end
        it 'calls stats without channel on a DM' do
          expect_any_instance_of(Team).to receive(:stats).with({})
          post '/api/discord/command',
               command: '/strada',
               text: 'stats',
               channel_id: 'DM',
               channel_name: 'channel_name',
               user_id: user.user_id,
               guild_id: team.guild_id,
               token: token
        end
      end
      context 'in channel' do
        before do
          allow_any_instance_of(Team).to receive(:bot_in_channel?).and_return(true)
        end
        context 'disconnected user' do
          let!(:club_in_another_channel) { Fabricate(:club, team: team, channel_id: 'another') }
          let!(:club) { Fabricate(:club, team: team, channel_id: 'channel') }
          it 'lists clubs connected to this channel' do
            post '/api/discord/command',
                 command: '/strada',
                 text: 'clubs',
                 channel_id: 'channel',
                 channel_name: 'channel_name',
                 user_id: user.user_id,
                 guild_id: team.guild_id,
                 token: token
            expect(last_response.status).to eq 201
            expect(JSON.parse(last_response.body)).to eq(
              JSON.parse(club.connect_to_discord.merge(
                text: '',
                user: user.user_id,
                channel: 'channel'
              ).to_json)
            )
          end
        end
        context 'connected user' do
          let(:user) { Fabricate(:user, team: team, access_token: 'token', token_expires_at: Time.now + 1.day) }
          let(:nyrr_club) do
            Club.new(
              strava_id: '108605',
              name: 'New York Road Runners',
              url: 'nyrr',
              city: 'New York',
              state: 'New York',
              country: 'United States',
              member_count: 9131,
              logo: 'https://dgalywyr863hv.cloudfront.net/pictures/clubs/108605/8433029/1/medium.jpg'
            )
          end
          it 'lists clubs a user is a member of', vcr: { cassette_name: 'strava/list_athlete_clubs' } do
            post '/api/discord/command',
                 command: '/strada',
                 text: 'clubs',
                 channel_id: 'channel',
                 channel_name: 'channel_name',
                 user_id: user.user_id,
                 guild_id: team.guild_id,
                 token: token
            expect(last_response.status).to eq 201
            response = JSON.parse(last_response.body)
            expect(response['attachments'].count).to eq 5
            expect(response['attachments'][0]['title']).to eq nyrr_club.name
          end
          context 'with another connected club in the channel' do
            let!(:club_in_another_channel) { Fabricate(:club, team: team, channel_id: 'another') }
            let!(:club) { Fabricate(:club, team: team, channel_id: 'channel') }
            it 'lists both clubs a user is a member of and the connected club', vcr: { cassette_name: 'strava/list_athlete_clubs' } do
              post '/api/discord/command',
                   command: '/strada',
                   text: 'clubs',
                   channel_id: 'channel',
                   channel_name: 'channel_name',
                   user_id: user.user_id,
                   guild_id: team.guild_id,
                   token: token
              response = JSON.parse(last_response.body)
              expect(response['attachments'].count).to eq 6
              expect(response['attachments'][0]['title']).to eq nyrr_club.name
              expect(response['attachments'][1]['title']).to eq club.name
            end
          end
        end
        context 'out of channel' do
          before do
            allow_any_instance_of(Team).to receive(:bot_in_channel?).and_return(false)
          end
          let!(:club) { Fabricate(:club, team: team, channel_id: 'channel') }
          it 'requires the bot to be a member' do
            post '/api/discord/command',
                 command: '/strada',
                 text: 'clubs',
                 channel_id: 'channel',
                 channel_name: 'channel_name',
                 user_id: user.user_id,
                 guild_id: team.guild_id,
                 token: token
            response = JSON.parse(last_response.body)
            expect(response['text']).to eq 'Please invite <@strada> to this channel before connecting a club.'
          end
        end
        context 'DMs' do
          it 'says no clubs are connected in a DM' do
            post '/api/discord/command',
                 command: '/strada',
                 text: 'clubs',
                 channel_id: 'D1234',
                 channel_name: 'channel_name',
                 user_id: user.user_id,
                 guild_id: team.guild_id,
                 token: token

            expect(last_response.status).to eq 201
            expect(JSON.parse(last_response.body)).to eq(
              'attachments' => [],
              'channel' => 'D1234',
              'text' => 'No clubs connected. To connect a club, invite <@strada> to a channel and use `/strada clubs`.',
              'user' => user.user_id
            )
          end
          context 'with a connected club' do
            let!(:club) { Fabricate(:club, team: team) }
            it 'lists connected clubs in a DM' do
              post '/api/discord/command',
                   command: '/strada',
                   text: 'clubs',
                   channel_id: 'D1234',
                   channel_name: 'channel_name',
                   user_id: user.user_id,
                   guild_id: team.guild_id,
                   token: token

              expect(last_response.status).to eq 201
              club_with_channel_id = club.to_discord
              club_with_channel_id[:attachments].each do |attachment|
                attachment[:text] += "\n#{club.channel_mention}"
              end
              expect(JSON.parse(last_response.body)).to eq(
                JSON.parse(club_with_channel_id.merge(
                  text: 'To connect a club, invite <@strada> to a channel and use `/strada clubs`.',
                  user: user.user_id,
                  channel: 'D1234'
                ).to_json)
              )
            end
          end
        end
      end
      it 'returns an error with a non-matching verification token' do
        post '/api/discord/command',
             command: '/strada',
             text: 'clubs',
             channel_id: 'C1',
             channel_name: 'channel_1',
             user_id: 'user_id',
             guild_id: 'guild_id',
             token: 'invalid-token'
        expect(last_response.status).to eq 401
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq 'Message token is not coming from Discord.'
      end
      it 'provides a connect link' do
        post '/api/discord/command',
             command: '/strada',
             text: 'connect',
             channel_id: 'channel',
             channel_name: 'channel_1',
             user_id: user.user_id,
             guild_id: team.guild_id,
             token: token
        expect(last_response.status).to eq 201
        url = "https://www.strava.com/oauth/authorize?client_id=client-id&redirect_uri=https://strada.playplay.io/connect&response_type=code&scope=activity:read_all&state=#{user.id}"
        expect(last_response.body).to eq({
          text: 'Please connect your Strava account.',
          attachments: [{
            fallback: "Please connect your Strava account at #{url}.",
            actions: [{
              type: 'button',
              text: 'Click Here',
              url: url
            }]
          }],
          user: user.user_id,
          channel: 'channel'
        }.to_json)
      end
      it 'attempts to disconnect' do
        post '/api/discord/command',
             command: '/strada',
             text: 'disconnect',
             channel_id: 'channel',
             channel_name: 'channel_name',
             user_id: user.user_id,
             guild_id: team.guild_id,
             token: token
        expect(last_response.status).to eq 201
        expect(last_response.body).to eq({
          text: 'Your Strava account is not connected.',
          user: user.user_id,
          channel: 'channel'
        }.to_json)
      end
    end
    context 'discord events' do
      let(:user) { Fabricate(:user, team: team) }
      it 'returns an error with a non-matching verification token' do
        post '/api/discord/event',
             type: 'url_verification',
             challenge: 'challenge',
             token: 'invalid-token'
        expect(last_response.status).to eq 401
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq 'Message token is not coming from Discord.'
      end
      it 'performs event challenge' do
        post '/api/discord/event',
             type: 'url_verification',
             challenge: 'challenge',
             token: token
        expect(last_response.status).to eq 201
        response = JSON.parse(last_response.body)
        expect(response).to eq('challenge' => 'challenge')
      end
      context 'with an activity' do
        let(:activity) { Fabricate(:user_activity, user: user) }
        before do
          allow(HTTParty).to receive_message_chain(:get, :body).and_return('PNG')
        end
        it 'unfurls a strava URL' do
          expect_any_instance_of(User).to receive(:sync_strava_activity!)
            .with(activity.strava_id)
            .and_return(activity)

          expect_any_instance_of(Discord::Web::Client).to receive(:chat_unfurl).with(
            channel: 'C1',
            ts: '1547842100.001400',
            unfurls: {
              activity.strava_url => activity.to_discord_embed
            }.to_json
          )

          post '/api/discord/event',
               token: token,
               guild_id: team.guild_id,
               api_app_id: 'A19GAJ72T',
               event: {
                 type: 'link_shared',
                 user: user.user_id,
                 channel: 'C1',
                 message_ts: '1547842100.001400',
                 links: [{
                   url: activity.strava_url,
                   domain: 'strava.com'
                 }]
               },
               type: 'event_callback',
               event_id: 'EvFGTNRKLG',
               event_time: 1_547_842_101,
               authed_users: ['U04KB5WQR']
          expect(last_response.status).to eq 201

          expect(activity.reload.bragged_at).to_not be nil
        end
      end
    end
    after do
      ENV.delete('SLACK_VERIFICATION_TOKEN')
    end
  end
  context 'with a dev discord verification token' do
    let(:token) { 'discord-verification-token' }
    let(:team) { Fabricate(:team) }
    before do
      ENV['SLACK_VERIFICATION_TOKEN_DEV'] = token
    end
    after do
      ENV.delete('SLACK_VERIFICATION_TOKEN_DEV')
    end
    context 'discord events' do
      let(:user) { Fabricate(:user, team: team) }
      it 'returns an error with a non-matching verification token' do
        post '/api/discord/event',
             type: 'url_verification',
             challenge: 'challenge',
             token: 'invalid-token'
        expect(last_response.status).to eq 401
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq 'Message token is not coming from Discord.'
      end
      it 'performs event challenge' do
        post '/api/discord/event',
             type: 'url_verification',
             challenge: 'challenge',
             token: token
        expect(last_response.status).to eq 201
        response = JSON.parse(last_response.body)
        expect(response).to eq('challenge' => 'challenge')
      end
    end
  end
end
