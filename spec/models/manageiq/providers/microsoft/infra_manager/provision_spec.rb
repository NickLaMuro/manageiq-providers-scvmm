describe ManageIQ::Providers::Microsoft::InfraManager::Provision do
  let(:vm_prov) do
    FactoryBot.create(
      :miq_provision_microsoft,
      :userid       => @admin.userid,
      :miq_request  => @pr,
      :source       => @vm_template,
      :request_type => 'template',
      :state        => 'pending',
      :status       => 'Ok',
      :options      => @options
    )
  end

  let(:regex) { ManageIQ::Providers::Microsoft::InfraManager::Provision::Cloning::MT_POINT_REGEX }

  context "MT_POINT_REGEX" do
    it "matches a storage name with a drive letter" do
      string = "file://foo.cfme-qe.redhat.com/J:/"
      expect(string.scan(regex).flatten.first).to eql("J:/")
    end

    it "matches a storage name with a drive letter and path" do
      string = "file://foo.cfme-qe.redhat.com/C:/ClusterStorage/netapp_crud_vol"
      expect(string.scan(regex).flatten.first).to eql("C:/ClusterStorage/netapp_crud_vol")
    end

    it "matches a storage name without a drive letter" do
      string = "file://foo123.redhat.com///clusterstore.xx-yy-redhat.com/cdrive"
      expect(string.scan(regex).flatten.first).to eql("//clusterstore.xx-yy-redhat.com/cdrive")
    end
  end

  context "A new provision request," do
    before(:each) do
      @os = OperatingSystem.new(:product_name => 'Microsoft Windows')
      @admin       = FactoryBot.create(:user_admin)
      @target_vm_name = 'clone test'
      @ems         = FactoryBot.create(:ems_microsoft_with_authentication)
      @vm_template = FactoryBot.create(
        :template_microsoft,
        :name                  => "template1",
        :ext_management_system => @ems,
        :operating_system      => @os,
        :cpu_limit             => -1,
        :cpu_reserve           => 0)
      @vm          = FactoryBot.create(:vm_microsoft, :name => "vm1",       :location => "abc/def.xml")
      @pr          = FactoryBot.create(:miq_provision_request, :requester => @admin, :src_vm_id => @vm_template.id)
      @options = {
        :pass           => 1,
        :vm_name        => @target_vm_name,
        :vm_target_name => @target_vm_name,
        :number_of_vms  => 1,
        :cpu_limit      => -1,
        :cpu_reserve    => 0,
        :provision_type => "microsoft",
        :src_vm_id      => [@vm_template.id, @vm_template.name]
      }
    end

    context "SCVMM provisioning" do
      it "#workflow" do
        workflow_class = ManageIQ::Providers::Microsoft::InfraManager::ProvisionWorkflow
        allow_any_instance_of(workflow_class).to receive(:get_dialogs).and_return(:dialogs => {})

        expect(vm_prov.workflow.class).to eq workflow_class
        expect(vm_prov.workflow_class).to eq workflow_class
      end
    end

    context "#prepare_for_clone_task" do
      before do
        @host = FactoryBot.create(:host_microsoft, :ems_ref => "test_ref")
        allow(vm_prov).to receive(:dest_host).and_return(@host)
      end

      it "with default options" do
        clone_options = vm_prov.prepare_for_clone_task
        expect(clone_options[:name]).to eq(@target_vm_name)
        expect(clone_options[:host]).to eq(@host)
      end
    end

    context "#parse mount point" do
      before do
        ds_name = "file://server.local/C:/ClusterStorage/CLUSP04%20Prod%20Volume%203-1"
        @datastore = FactoryBot.create(:storage, :name => ds_name)
        allow(vm_prov).to receive(:dest_datastore).and_return(@datastore)
      end

      it "valid drive" do
        expect(vm_prov.dest_mount_point).to eq("C:\\ClusterStorage\\CLUSP04 Prod Volume 3-1")
      end
    end

    context "#no network adapter available" do
      it "set adapter" do
        expect(vm_prov.network_adapter_ps_script).to be_nil
      end
    end

    context "#network adapter available" do
      before do
        @switch = FactoryBot.create(:switch, :name => 'switch1')

        @logical_network = FactoryBot.create(
          :lan,
          :name    => 'virtualnetwork1',
          :uid_ems => '53f38ddc-450e-4f43-abde-881ac44608e3',
          :switch  => @switch
        )

        @vm_network = FactoryBot.create(
          :lan,
          :name    => 'virtualnetwork1-vm-network',
          :uid_ems => '243f2689-f6ef-401e-b875-41ba4c351c60',
          :parent  => @logical_network,
          :switch  => @switch
        )

        host = FactoryBot.create(:host_microsoft, :ems_ref => "test_ref")
        host.switches = [@switch]

        @options[:vlan] = [@logical_network.uid_ems, @logical_network.name]
        allow(vm_prov).to receive(:dest_host).and_return(host)
      end

      it "set adapter" do
        expect(vm_prov.network_adapter_ps_script).to_not be_nil
      end
    end

    context "#no cpu limit or reservation set" do
      before do
        @options[:number_of_sockets] = 2
        @options[:cpu_limit]      = nil
        @options[:cpu_reserve]    = nil
      end

      it "set vm" do
        expect(vm_prov.cpu_ps_script).to eq("-CPUCount 2 ")
      end
    end

    context "#cpu limit set" do
      before do
        @options[:cpu_limit]      = 40
        @options[:cpu_reserve]    = nil
        @options[:number_of_sockets] = 2
      end

      it "set vm" do
        expect(vm_prov.cpu_ps_script).to eq("-CPUCount 2 -CPUMaximumPercent 40 ")
      end
    end

    context "#cpu reservations set" do
      before do
        @options[:cpu_reserve]    = 15
        @options[:cpu_limit]      = nil
        @options[:number_of_sockets] = 2
      end

      it "set vm" do
        expect(vm_prov.cpu_ps_script).to eq("-CPUCount 2 -CPUReserve 15 ")
      end
    end
  end
end
