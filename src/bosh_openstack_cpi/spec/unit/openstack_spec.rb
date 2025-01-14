require 'spec_helper'

describe Bosh::OpenStackCloud::Openstack do
  let(:openstack_options_v2) { mock_cloud_options['properties']['openstack'] }
  let(:openstack_options_v2_devstack) { mock_cloud_options(2, true)['properties']['openstack'] }
  let(:openstack_options_v3) { mock_cloud_options(3)['properties']['openstack'] }
  let(:openstack_options_v3_devstack) { mock_cloud_options(3, true)['properties']['openstack'] }
  let(:openstack_options) { openstack_options_v2 }
  subject(:subject) { Bosh::OpenStackCloud::Openstack.new(openstack_options) }

  describe 'is_v3' do
    it 'should identify keystone v3 URIs' do
      expect(Bosh::OpenStackCloud::Openstack.is_v3('http://fake-auth-url/v3')).to be_truthy
    end

    it 'should identify keystone v2 URIs' do
      expect(Bosh::OpenStackCloud::Openstack.is_v3('http://fake-auth-url/v2.0')).to be_falsey
    end
  end

  describe :project_name do

    context 'when keystone version is v2' do
      let(:openstack_options) { openstack_options_v2 }
      it 'returns the project name' do
        expect(subject.project_name).to eq('dummy_tenant')
      end
    end

    context 'when keystone version is v3' do
      let(:openstack_options) { openstack_options_v3 }
      it 'returns the tenant name' do
        expect(subject.project_name).to eq('dummy_project')
      end
    end
  end

  describe :new do
    context 'when auth_url does not include tokens' do
      context 'when auth_url is v2' do
        it 'should remove the auth_url version' do
          expect(subject.auth_url).to eq('http://127.0.0.1:5000')
        end
      end

      context 'when auth_url is a devstack v2' do
        let(:openstack_options) { openstack_options_v2_devstack }

        it 'should remove the auth_url version' do
          expect(subject.auth_url).to eq('http://127.0.0.1:5000/identity')
        end
      end

      context 'when auth_url is v3' do
        let(:openstack_options) { openstack_options_v3 }

        it 'should remove the auth_url version' do
          expect(subject.auth_url).to eq('http://127.0.0.1:5000')
        end
      end

      context 'when auth_url is a devstack v3 url' do
        let(:openstack_options) { openstack_options_v3_devstack }

        it 'should remove the auth_url version' do
          expect(subject.auth_url).to eq('http://127.0.0.1:5000/identity')
        end
      end
    end

    context 'when the full auth_url was specified' do
      context 'when auth_url is v2' do
        before do
          openstack_options_v2['auth_url'] = 'http://fake-auth-url/v2.0/tokens'
        end

        it 'removes everything beginning from auth_url version' do
          expect(subject.auth_url).to eq('http://fake-auth-url')
        end
      end

      context 'when auth_url is v2 devstack url' do
        before do
          openstack_options_v2['auth_url'] = 'http://fake-auth-url/identity/v2.0/tokens'
        end

        it 'removes everything beginning from the auth_url version' do
          expect(subject.auth_url).to eq('http://fake-auth-url/identity')
        end
      end

      context 'when auth_url is v3' do
        let(:openstack_options) { openstack_options_v3 }
        before do
          openstack_options_v3['auth_url'] = 'http://fake-auth-url/v3/auth/tokens'
        end

        it 'removes everything beginning from the auth_url version' do
          expect(subject.auth_url).to eq('http://fake-auth-url')
        end
      end

      context 'when auth_url is v3 devstack url' do
        let(:openstack_options) { openstack_options_v3 }
        before do
          openstack_options_v3['auth_url'] = 'http://fake-auth-url/identity/v3/auth/tokens'
        end

        it 'removes everything beginning from the auth_url version' do
          expect(subject.auth_url).to eq('http://fake-auth-url/identity')
        end
      end

      context 'and it ends with a slash' do
        before do
          openstack_options_v2['auth_url'] = 'http://fake-auth-url/v2.0/'
        end

        it 'removes the trailing slash and version' do
          expect(subject.auth_url).to eq('http://fake-auth-url')
        end
      end
    end

    context 'excon instrumentor' do
      context 'default instrumentor' do
        it 'set the default instrumentor' do
          openstack = Bosh::OpenStackCloud::Openstack.new(openstack_options)

          expect(openstack.params[:connection_options]['instrumentor']).to eq(Bosh::OpenStackCloud::ExconLoggingInstrumentor)
        end
      end

      context 'no instrumentor' do
        it 'set the default instrumentor' do
          openstack = Bosh::OpenStackCloud::Openstack.new(openstack_options, {}, {})

          expect(openstack.params[:connection_options].key?('instrumentor')).to be(false)
        end
      end
    end
  end

  describe :use_nova_networking? do
    context 'when the manifest contains `use_nova_networking=true`' do
      let(:openstack_options_with_nova) { openstack_options_v3['use_nova_networking'] = true; openstack_options_v3 }
      let(:openstack_options) { openstack_options_with_nova }
      it 'returns true' do
        expect(subject.use_nova_networking?).to eq(true)
      end
    end

    context 'when the manifest contains `use_nova_networking=false`' do
      let(:openstack_options_with_nova) { openstack_options_v3['use_nova_networking'] = false; openstack_options_v3 }
      let(:openstack_options) { openstack_options_with_nova }
      it 'returns false' do
        expect(subject.use_nova_networking?).to eq(false)
      end
    end

    context 'when the manifest does not contain `use_nova_networking`' do
      let(:openstack_options) { openstack_options_v3 }
      it 'returns false' do
        expect(subject.use_nova_networking?).to eq(false)
      end
    end
  end

  context 'when the service is not available' do
    describe 'Network' do
      it 'raises a CloudError exception if cannot connect to the service API' do
        allow(Fog::OpenStack::Network).to receive(:new).and_raise(Fog::Errors::NotFound, 'Not found message')
        expect {
          Bosh::OpenStackCloud::Openstack.new(openstack_options).network
        }.to raise_error(Bosh::Clouds::CloudError,
                         'Unable to connect to the OpenStack Network Service API: Not found message. Check task debug log for details.')
      end
    end
  end

  [{ clazz: Fog::OpenStack::Compute, name: 'Compute', method_name: :compute },
   { clazz: Fog::OpenStack::Image, name: 'Image', method_name: :image },
   { clazz: Fog::OpenStack::Volume, name: 'Volume', method_name: :volume },
   { clazz: Fog::OpenStack::Network, name: 'Network', method_name: :network }].each do |fog|
    describe (fog[:name]).to_s do
      let(:retry_options_overwrites) {
        {
          sleep: 0,
        } }

      context 'when the service returns Unauthorized' do
        it 'raises a CloudError exception if cannot connect to the service API 5 times' do
          allow(fog[:clazz]).to receive(:new).and_raise(Excon::Error::Unauthorized, 'Unauthorized')
          expect {
            Bosh::OpenStackCloud::Openstack.new(openstack_options, retry_options_overwrites).send(fog[:method_name])
          }.to raise_error(Bosh::Clouds::CloudError,
                           "Unable to connect to the OpenStack #{fog[:name]} Service API: Unauthorized. Check task debug log for details.")
        end
      end

      context 'when the backend call raises a SocketError' do
        let(:socket_error) { Excon::Error::Socket.new(SocketError.new('getaddrinfo: nodename nor servname provided, or not known')) }
        let(:expected_error_message) { "Unable to connect to the OpenStack Keystone API http://127.0.0.1:5000\ngetaddrinfo: nodename nor servname provided, or not known (SocketError)" }

        it 'raises a CloudError exception enriched with the targeted OpenStack KeyStone API url for service API' do
          allow(fog[:clazz]).to receive(:new).and_raise(socket_error)

          expect {
            Bosh::OpenStackCloud::Openstack.new(openstack_options, retry_options_overwrites).send(fog[:method_name])
          }.to raise_error(Bosh::Clouds::CloudError, expected_error_message)
        end
      end

      context 'with connection options' do
        let(:connection_options) { { 'ssl_verify_peer' => false } }
        let(:default_connection_options) {
          { 'instrumentor' => Bosh::OpenStackCloud::ExconLoggingInstrumentor }
        }
        let(:merged_connection_options) {
          default_connection_options.merge(connection_options)
        }

        it 'should add optional options to the Fog connection' do
          openstack_options['connection_options'] = connection_options

          allow(fog[:clazz]).to receive(:new).and_return(instance_double(fog[:clazz]))
          Bosh::OpenStackCloud::Openstack.new(openstack_options).send(fog[:method_name])

          expect(fog[:clazz]).to have_received(:new).with(hash_including(connection_options: merged_connection_options))
        end
      end

      context 'when keystone V3 API is used' do
        let(:openstack_options) { openstack_options_v3 }
        it 'should add optional options to the Fog connection' do
          allow(fog[:clazz]).to receive(:new).and_return(instance_double(fog[:clazz]))
          Bosh::OpenStackCloud::Openstack.new(openstack_options).send(fog[:method_name])

          expect(fog[:clazz]).to have_received(:new).with(hash_including(openstack_project_name: 'dummy_project'))
          expect(fog[:clazz]).to have_received(:new).with(hash_including(openstack_domain_name: 'some_domain'))
        end
      end

      context 'when keystone V2 API is used' do
        it 'should add optional options to the Fog connection' do
          allow(fog[:clazz]).to receive(:new).and_return(instance_double(fog[:clazz]))
          Bosh::OpenStackCloud::Openstack.new(openstack_options).send(fog[:method_name])

          expect(fog[:clazz]).to have_received(:new).with(hash_including(openstack_tenant: 'dummy_tenant'))
        end
      end

      context 'when last retry succeeds' do
        before do
          retry_count = 0
          allow(fog[:clazz]).to receive(:new) do
            retry_count += 1
            if retry_count < Bosh::OpenStackCloud::Cloud::CONNECT_RETRY_COUNT
              raise Excon::Error::GatewayTimeout, 'Gateway Timeout'
            end
            instance_double(fog[:clazz])
          end
        end

        it 'does not raise a GatewayTimeout error' do
          expect {
            Bosh::OpenStackCloud::Openstack.new(openstack_options)
          }.to_not raise_error
        end
      end

      context 'when used multiple times' do
        it 'creates the connection lazy and caches it' do
          expect(fog[:clazz]).to receive(:new).once.and_return(instance_double(fog[:clazz]))
          openstack = Bosh::OpenStackCloud::Openstack.new(openstack_options)

          fog_class_1st_call = openstack.send(fog[:method_name])
          fog_class_2nd_call = openstack.send(fog[:method_name])

          expect(fog_class_1st_call).to eq fog_class_2nd_call
        end
      end
    end
  end

  describe 'wait_resource' do
    let(:resource) { double('resource', id: 'foobar', reload: {}) }
    before { allow(resource).to receive(:status).and_return(:start, :stop) }
    before { allow(subject).to receive(:sleep) }

    it 'does not raise if one of the target states is reached' do
      expect {
        subject.wait_resource(resource, %i[stop deleted], :status, false)
      }.to_not raise_error
    end

    it 'waits for configured amount of time' do
      expect(subject).to receive(:sleep).with(3)

      subject.wait_resource(resource, %i[stop deleted], :status, false)
    end

    context 'when the resource status never changes' do
      it 'times out' do
        start_time = Time.now
        timeout_time = start_time + subject.state_timeout + 1
        Timecop.freeze(start_time)

        allow(resource).to receive(:status) do
          Timecop.freeze(timeout_time)
          :start
        end

        expect {
          subject.wait_resource(resource, :stop, :status, false)
        }.to raise_error Bosh::Clouds::CloudError, /Timed out/
      end
    end

    context 'when the resource status is error' do
      before { allow(resource).to receive(:status).and_return(:error) }
      context 'when no additional fault is provided by OpenStack' do
        before { allow(resource).to receive(:fault).and_return(nil) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is error/
        end
      end

      context 'when no additional fault supported by resource' do
        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is error/
        end
      end

      context 'when additional fault is provided by OpenStack' do
        let(:resource) { double('resource', id: 'foobar', reload: {}, fault: { 'message' => 'fault message ', 'details' => 'fault details' }) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is error, expected stop\nfault message fault details/
        end
      end
    end

    context 'when the resource status is failed' do
      before { allow(resource).to receive(:status).and_return(:failed) }
      context 'when no additional fault is provided by OpenStack' do
        before { allow(resource).to receive(:fault).and_return(nil) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is failed/
        end
      end

      context 'when no additional fault supported by resource' do
        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is failed/
        end
      end

      context 'when additional fault is provided by OpenStack' do
        let(:resource) { double('resource', id: 'foobar', reload: {}, fault: { 'message' => 'fault message ', 'details' => 'fault details' }) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is failed, expected stop\nfault message fault details/
        end
      end
    end

    context 'when the resource status is killed' do
      before { allow(resource).to receive(:status).and_return(:killed) }
      context 'when no additional fault is provided by OpenStack' do
        before { allow(resource).to receive(:fault).and_return(nil) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is killed/
        end
      end

      context 'when no additional fault supported by resource' do
        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is killed/
        end
      end

      context 'when additional fault is provided by OpenStack' do
        let(:resource) { double('resource', id: 'foobar', reload: {}, fault: { 'message' => 'fault message ', 'details' => 'fault details' }) }

        it 'raises Bosh::Clouds::CloudError' do
          expect {
            subject.wait_resource(resource, :stop, :status, false)
          }.to raise_error Bosh::Clouds::CloudError, /state is killed, expected stop\nfault message fault details/
        end
      end
    end

    context 'when the resource is not found' do
      before { allow(resource).to receive(:reload).and_return(nil) }

      it 'should raise Bosh::Clouds::CloudError if resource not found' do
        expect {
          subject.wait_resource(resource, :deleted, :status, false)
        }.to raise_error Bosh::Clouds::CloudError, /Resource not found/
      end

      context 'when the resource does not need to be found' do
        it 'does not raise' do
          expect { subject.wait_resource(resource, :deleted, :status, true) }.not_to raise_error
        end
      end
    end
  end

  describe 'with_openstack' do
    context 'when openstack raises an unexpected exception' do
      before { allow(subject).to receive(:servers).and_raise(NoMemoryError) }

      it 'raises the exception without waiting' do
        expect(subject).not_to receive(:sleep)

        expect {
          subject.with_openstack do
            subject.servers
          end
        }.to raise_error(NoMemoryError)
      end
    end

    context 'when openstack raises ServiceUnavailable' do
      let(:headers) { {} }
      let(:body) do
        {
          'overLimit' => {
            'message' => 'No server is available to handle this request.',
            'code' => 503,
          },
        }
      end
      let(:response) { Excon::Response.new(body: JSON.dump(body), headers:) }

      before do
        allow(subject).to receive(:servers) do
          # next time don't raise the same exception to avoid looping
          allow(subject).to receive(:servers).and_return(nil)

          raise Excon::Error::ServiceUnavailable.new('', '', response)
        end
      end

      it 'retries until the max number of retries is reached' do
        allow(subject).to receive(:servers).exactly(11).times
                                           .and_raise(Excon::Error::ServiceUnavailable.new('', '', response))
        expect(subject).to receive(:sleep).with(3).exactly(10).times

        expect {
          subject.with_openstack do
            subject.servers
          end
        }.to raise_error(Bosh::Clouds::CloudError,
                         "OpenStack API ServiceUnavailable.\nCheck task debug log for details.")
      end
    end

    context 'when openstack raises RequestEntityTooLarge' do
      let(:headers) { {} }
      let(:body) do
        {
          'overLimit' => {
            'message' => 'This request was rate-limited.',
            'code' => 413,
            'details' => 'Only 10 POST request(s) can be made to * every minute.',
          },
        }
      end
      let(:response) { Excon::Response.new(body: JSON.dump(body), headers:) }

      before do
        allow(subject).to receive(:servers) do
          # next time don't raise the same exception to avoid looping
          allow(subject).to receive(:servers).and_return(nil)

          raise Excon::Error::RequestEntityTooLarge.new('', '', response)
        end
      end

      it 'retries after waiting a default number of seconds' do
        expect_any_instance_of(Kernel).to receive(:sleep).with(3)

        subject.with_openstack do
          subject.servers
        end
      end

      it 'retries until the max number of retries is reached' do
        allow(subject).to receive(:servers).exactly(11).times
                                           .and_raise(Excon::Error::RequestEntityTooLarge.new('', '', response))
        expect_any_instance_of(Kernel).to receive(:sleep).with(3).exactly(10).times

        expect {
          subject.with_openstack do
            subject.servers
          end
        }.to raise_error(Bosh::Clouds::CloudError,
                         /OpenStack API RequestEntityTooLarge/)
      end

      context 'when the response includes a retryAfter in the body' do
        before { body['overLimit']['retryAfter'] = 5 }

        it 'retries after waiting the amount of seconds received at the response body' do
          expect_any_instance_of(Kernel).to receive(:sleep).with(5)

          subject.with_openstack do
            subject.servers
          end
        end
      end

      context 'when the response includes a Retry-After header' do
        before { headers['Retry-After'] = 5 }

        it 'retries after waiting the amount of seconds received in the Retry-After header' do
          expect_any_instance_of(Kernel).to receive(:sleep).with(5)

          subject.with_openstack do
            subject.servers
          end
        end
      end

      context 'when OpenStack error message contains overLimit,' do
        let(:body) do
          {
            'overLimit' => {
              'message' => 'Specific OpenStack error message',
              'code' => 413,
              'details' => 'Only 10 POST request(s) can be made to * every minute.',
              'retryAfter' => 0,
            },
          }
        end

        it 'enriches the BOSH error message' do
          allow(subject).to receive(:servers).and_raise(Excon::Error::RequestEntityTooLarge.new('', '', response))

          expected_message = "OpenStack API RequestEntityTooLarge Specific OpenStack error message.\nCheck task debug log for details."

          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError, expected_message)
        end
      end

      context 'when OpenStack error message does not contain overLimit,' do
        let(:body) do
          {
            'notOverLimit' => 'arbitrary content',
          }
        end

        it 'enriches the BOSH error message with the whole response body' do
          expected_response_body = JSON.dump('notOverLimit' => 'arbitrary content')
          expected_message = "OpenStack API RequestEntityTooLarge #{expected_response_body}.\nCheck task debug log for details."

          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError, expected_message)
        end
      end
    end

    context 'when openstack raises BadRequest' do
      before do
        response = Excon::Response.new(body:)
        expect(subject).to receive(:servers).and_raise(Excon::Error::BadRequest.new('', '', response))
      end

      let(:body) { JSON.dump({}) }

      context 'when the error includes a `message` property on 2nd level of body' do
        let(:body) { JSON.dump('SomeError' => { 'message' => 'some-message' }) }

        it 'should raise a CloudError exception with OpenStack API message' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API BadRequest (some-message).\nCheck task debug log for details.")
        end
      end

      context 'when the error does not include a message' do
        let(:body) { JSON.dump('SomeError' => { 'some_key' => 'some_val' }) }

        it 'should raise a CloudError exception with OpenStack API message without anything from body' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API BadRequest.\nCheck task debug log for details.")
        end
      end

      context 'when the response has an empty body' do
        let(:body) { '' }

        it 'should raise a CloudError exception without OpenStack API message' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API BadRequest.\nCheck task debug log for details.")
        end
      end
    end

    context 'when openstack raises Conflict' do
      before do
        response = Excon::Response.new(body:)
        expect(subject).to receive(:servers).and_raise(Excon::Error::Conflict.new('', '', response))
      end

      let(:body) { JSON.dump({}) }

      context 'when the error includes a `message` property on 2nd level of body' do
        let(:body) { JSON.dump('SomeError' => { 'message' => 'some-message' }) }

        it 'should raise a CloudError exception with OpenStack API message' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Conflict (some-message).\nCheck task debug log for details.")
        end
      end

      context 'when the error does not include a message' do
        let(:body) { JSON.dump('SomeError' => { 'some_key' => 'some_val' }) }

        it 'should raise a CloudError exception with OpenStack API message without anything from body' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Conflict.\nCheck task debug log for details.")
        end
      end

      context 'when the response has an empty body' do
        let(:body) { '' }

        it 'should raise a CloudError exception without OpenStack API message' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Conflict.\nCheck task debug log for details.")
        end
      end
    end

    context 'when openstack raises InternalServerError' do
      it 'should retry the max number of retries before raising a CloudError exception' do
        expect(subject).to receive(:servers).exactly(11)
                                            .and_raise(Excon::Error::InternalServerError.new('InternalServerError'))
        expect_any_instance_of(Kernel).to receive(:sleep).with(3).exactly(10)

        expect {
          subject.with_openstack do
            subject.servers
          end
        }.to raise_error(Bosh::Clouds::CloudError,
                         "OpenStack API InternalServerError.\nCheck task debug log for details.")
      end
    end

    context 'when openstack raises Fog::Errors::NotFound' do
      it 'should raise a CloudError with the original OpenStack message' do
        openstack_error_message = 'Could not find service network. Have compute, compute_legacy, identity, image, volume'

        expect {
          subject.with_openstack { raise Fog::Errors::NotFound, openstack_error_message }
        }.to raise_error(Bosh::Clouds::CloudError,
                         "OpenStack API NotFound #{openstack_error_message}.\nCheck task debug log for details.")
      end

      context 'when NotFound is ignored' do
        it 'should not raise a CloudError' do
          expect {
            subject.with_openstack(ignore_not_found: true) { raise Fog::Errors::NotFound }
          }.to_not raise_error
        end
      end
    end

    context 'when openstack raises Forbidden' do
      before do
        response = Excon::Response.new(body:)
        expect(subject).to receive(:servers).and_raise(Excon::Error::Forbidden.new('', '', response))
      end

      let(:body) { JSON.dump({}) }

      context 'when the error includes a `message` property on 2nd level of body' do
        let(:body) { JSON.dump('Forbidden' => { 'message' => 'some-message' }) }

        it 'should raise a CloudError exception with OpenStack API message' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Forbidden (some-message).\nCheck task debug log for details.")
        end
      end

      context 'when the error does not include a message' do
        let(:body) { JSON.dump('SomeError' => { 'some_key' => 'some_val' }) }

        it 'should raise a CloudError exception with OpenStack API message without anything from body' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Forbidden.\nCheck task debug log for details.")
        end
      end

      context 'when the response has an empty body' do
        let(:body) { '' }

        it 'should raise a CloudError exception with OpenStack API message without anything from body' do
          expect {
            subject.with_openstack do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Forbidden.\nCheck task debug log for details.")
        end
      end
    end

    context 'when error is Excon::Error::Timeout' do
      before do
        allow(subject).to receive(:servers).and_raise(Excon::Error::Timeout.new('foo'))
        stub_const("Bosh::OpenStackCloud::Openstack::DEFAULT_RETRY_TIMEOUT", 0)
      end

      context 'when request is retryable' do
        it 'should retry request MAX_RETRIES times' do
          expect {
            subject.with_openstack(retryable: true) do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Timeout foo.\nCheck task debug log for details.")

          expect(subject).to have_received(:servers).exactly(Bosh::OpenStackCloud::Openstack::MAX_RETRIES + 1).times
        end
      end

      context 'when request is not retryable' do
        it 'should retry request MAX_RETRIES times' do
          expect {
            subject.with_openstack(retryable: false) do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Timeout foo.\nCheck task debug log for details.")

          expect(subject).to have_received(:servers).once
        end
      end
    end

    context 'when error is Excon::Error::Socket' do
      before do
        stub_const("Bosh::OpenStackCloud::Openstack::DEFAULT_RETRY_TIMEOUT", 0)
      end

      context "when a SocketError is raised with 'getaddrinfo'" do
        before do
          allow(subject).to receive(:servers).and_raise(Excon::Error::Socket.new(SocketError.new('getaddrinfo: nodename nor servname provided, or not known')))
        end

        it 'should retry request MAX_RETRIES times' do
          expect {
            subject.with_openstack(retryable: false) do
              subject.servers
            end
          }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Socket getaddrinfo: nodename nor servname provided, or not known (SocketError).\nCheck task debug log for details.")

          expect(subject).to have_received(:servers).exactly(Bosh::OpenStackCloud::Openstack::MAX_RETRIES + 1).times
        end
      end

      context "when a SocketError is not raised with 'getaddrinfo'" do
        before do
          allow(subject).to receive(:servers).and_raise(Excon::Error::Socket.new(SocketError.new('foo')))
        end

        context 'when request is retryable' do
          it 'should retry request MAX_RETRIES times' do
            expect {
              subject.with_openstack(retryable: true) do
                subject.servers
              end
            }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Socket foo (SocketError).\nCheck task debug log for details.")

            expect(subject).to have_received(:servers).exactly(Bosh::OpenStackCloud::Openstack::MAX_RETRIES + 1).times
          end
        end

        context 'when request is not retryable' do
          it 'should not retry request' do
            expect {
              subject.with_openstack(retryable: false) do
                subject.servers
              end
            }.to raise_error(Bosh::Clouds::CloudError,
                           "OpenStack API Socket foo (SocketError).\nCheck task debug log for details.")

            expect(subject).to have_received(:servers).once
          end
        end
      end
    end
  end

  describe 'parse_openstack_response' do
    it 'should return nil if response has no body' do
      response = Excon::Response.new

      expect(subject.parse_openstack_response(response, 'key')).to be_nil
    end

    it 'should return nil if response has an empty string body' do
      response = Excon::Response.new(body: JSON.dump(''))

      expect(subject.parse_openstack_response(response, 'key')).to be_nil
    end

    it 'should return nil if response has a nil body' do
      response = Excon::Response.new(body: JSON.dump(nil))

      expect(subject.parse_openstack_response(response, 'key')).to be_nil
    end

    it 'should return nil if response is not JSON' do
      response = Excon::Response.new(body: 'foo = bar')

      expect(subject.parse_openstack_response(response, 'key')).to be_nil
    end

    it 'should return nil if response is no key is found' do
      response = Excon::Response.new(body: JSON.dump('foo' => 'bar'))

      expect(subject.parse_openstack_response(response, 'key')).to be_nil
    end

    it 'should return the contents if key is found' do
      response = Excon::Response.new(body: JSON.dump('key' => 'foo'))

      expect(subject.parse_openstack_response(response, 'key')).to eql('foo')
    end

    it 'should return the contents of the first key found' do
      response = Excon::Response.new(body: JSON.dump('key1' => 'foo', 'key2' => 'bar'))

      expect(subject.parse_openstack_response(response, 'key2', 'key1')).to eql('bar')
    end
  end
end
