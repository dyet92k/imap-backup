describe Imap::Backup::Account::Connection do
  def self.backup_folder
    "backup_folder"
  end

  def self.folder_config
    {name: backup_folder}
  end

  subject { described_class.new(options) }

  let(:imap) do
    instance_double(Net::IMAP, login: nil, disconnect: nil)
  end
  let(:imap_folders) { [] }
  let(:options) do
    {
      username: username,
      password: "password",
      local_path: local_path,
      folders: backup_folders
    }
  end
  let(:local_path) { "local_path" }
  let(:backup_folders) { [self.class.folder_config] }
  let(:username) { "username@gmail.com" }
  let(:root_info) do
    instance_double(Net::IMAP::MailboxList, name: root_name)
  end
  let(:root_name) { "foo" }
  let(:serializer) do
    instance_double(
      Imap::Backup::Serializer::Mbox,
      folder: serialized_folder,
      force_uid_validity: nil,
      apply_uid_validity: new_uid_validity,
      uids: [local_uid]
    )
  end
  let(:serialized_folder) { nil }
  let(:new_uid_validity) { nil }
  let(:local_uid) { "local_uid" }

  before do
    allow(Net::IMAP).to receive(:new) { imap }
    allow(imap).to receive(:list).with("", "") { [root_info] }
    allow(imap).to receive(:list).with(root_name, "*") { imap_folders }
    allow(Imap::Backup::Utils).to receive(:make_folder)
  end

  shared_examples "connects to IMAP" do
    it "logs in to the imap server" do
      expect(imap).to have_received(:login)
    end
  end

  describe "#initialize" do
    [
      [:username, "username@gmail.com"],
      [:local_path, "local_path"],
      [:backup_folders, [folder_config]]
    ].each do |attr, expected|
      it "expects #{attr}" do
        expect(subject.send(attr)).to eq(expected)
      end
    end

    it "creates the path" do
      expect(Imap::Backup::Utils).to receive(:make_folder)

      subject.username
    end
  end

  describe "#imap" do
    let!(:result) { subject.imap }

    it "returns the IMAP connection" do
      expect(result).to eq(imap)
    end

    include_examples "connects to IMAP"
  end

  describe "#folders" do
    let(:imap_folders) do
      [instance_double(Net::IMAP::MailboxList)]
    end

    it "returns the list of folders" do
      expect(subject.folders).to eq(imap_folders)
    end
  end

  describe "#status" do
    let(:folder) do
      instance_double(Imap::Backup::Account::Folder, uids: [remote_uid])
    end
    let(:remote_uid) { "remote_uid" }

    before do
      allow(Imap::Backup::Account::Folder).to receive(:new) { folder }
      allow(Imap::Backup::Serializer::Mbox).to receive(:new) { serializer }
    end

    it "returns the names of folders" do
      expect(subject.status[0][:name]).to eq(self.class.backup_folder)
    end

    it "returns local message uids" do
      expect(subject.status[0][:local]).to eq([local_uid])
    end

    it "retrieves the available uids" do
      expect(subject.status[0][:remote]).to eq([remote_uid])
    end
  end

  describe "#run_backup" do
    let(:folder) do
      instance_double(
        Imap::Backup::Account::Folder,
        name: "folder",
        exist?: exists,
        uid_validity: uid_validity
      )
    end
    let(:exists) { true }
    let(:uid_validity) { 123 }
    let(:downloader) { instance_double(Imap::Backup::Downloader, run: nil) }

    before do
      allow(Imap::Backup::Downloader).
        to receive(:new).with(folder, serializer) { downloader }
    end

    context "with supplied backup_folders" do
      before do
        allow(Imap::Backup::Account::Folder).to receive(:new).
          with(subject, self.class.backup_folder) { folder }
        allow(Imap::Backup::Serializer::Mbox).to receive(:new).
          with(local_path, self.class.backup_folder) { serializer }
      end

      it "runs the downloader" do
        expect(downloader).to receive(:run)

        subject.run_backup
      end

      context "when a folder does not exist" do
        let(:exists) { false }

        it "does not run the downloader" do
          expect(downloader).to_not receive(:run)

          subject.run_backup
        end
      end
    end

    context "without supplied backup_folders" do
      let(:imap_folders) do
        [instance_double(Net::IMAP::MailboxList, name: "foo")]
      end

      before do
        allow(Imap::Backup::Account::Folder).to receive(:new).
          with(subject, "foo") { folder }
        allow(Imap::Backup::Serializer::Mbox).to receive(:new).
          with(local_path, "foo") { serializer }
      end

      context "when supplied backup_folders is nil" do
        let(:backup_folders) { nil }

        it "runs the downloader for each folder" do
          expect(downloader).to receive(:run).exactly(:once)

          subject.run_backup
        end
      end

      context "when supplied backup_folders is an empty list" do
        let(:backup_folders) { [] }

        it "runs the downloader for each folder" do
          expect(downloader).to receive(:run).exactly(:once)

          subject.run_backup
        end
      end

      context "when the imap server doesn't return folders" do
        let(:backup_folders) { nil }
        let(:imap_folders) { nil }

        it "does not fail" do
          expect { subject.run_backup }.to_not raise_error
        end
      end
    end
  end

  describe "#restore" do
    let(:folder) do
      instance_double(
        Imap::Backup::Account::Folder,
        create: nil,
        uids: uids,
        name: "my_folder",
        uid_validity: uid_validity
      )
    end
    let(:uids) { [99] }
    let(:uid_validity) { 123 }
    let(:serialized_folder) { "old name" }
    let(:uploader) do
      instance_double(Imap::Backup::Uploader, run: false)
    end
    let(:updated_uploader) do
      instance_double(Imap::Backup::Uploader, run: false)
    end
    let(:updated_folder) do
      instance_double(
        Imap::Backup::Account::Folder,
        create: nil,
        uid_validity: "new uid validity"
      )
    end
    let(:updated_serializer) do
      instance_double(
        Imap::Backup::Serializer::Mbox, force_uid_validity: nil
      )
    end

    before do
      allow(Imap::Backup::Account::Folder).to receive(:new).
        with(subject, "my_folder") { folder }
      allow(Imap::Backup::Serializer::Mbox).to receive(:new).
        with(anything, "my_folder") { serializer }
      allow(Imap::Backup::Account::Folder).to receive(:new).
        with(subject, "new name") { updated_folder }
      allow(Imap::Backup::Serializer::Mbox).to receive(:new).
        with(anything, "new name") { updated_serializer }
      allow(Imap::Backup::Uploader).to receive(:new).
        with(folder, serializer) { uploader }
      allow(Imap::Backup::Uploader).to receive(:new).
        with(updated_folder, updated_serializer) { updated_uploader }
      allow(Pathname).to receive(:glob).
        and_yield(Pathname.new(File.join(local_path, "my_folder.imap")))
    end

    it "sets local uid validity" do
      expect(serializer).to receive(:apply_uid_validity).with(uid_validity)

      subject.restore
    end

    context "when folders exist with contents" do
      context "when the local folder is renamed" do
        let(:new_uid_validity) { "new name" }

        it "creates the new folder" do
          expect(updated_folder).to receive(:create)

          subject.restore
        end

        it "sets the renamed folder's uid validity" do
          expect(updated_serializer).
            to receive(:force_uid_validity).with("new uid validity")

          subject.restore
        end

        it "creates the uploader with updated folder and serializer" do
          expect(updated_uploader).to receive(:run)

          subject.restore
        end
      end

      context "when the local folder is not renamed" do
        it "runs the uploader" do
          expect(uploader).to receive(:run)

          subject.restore
        end
      end
    end

    context "when folders don't exist or are empty" do
      let(:uids) { [] }

      it "creates the folder" do
        expect(folder).to receive(:create)

        subject.restore
      end

      it "forces local uid validity" do
        expect(serializer).to receive(:force_uid_validity).with(uid_validity)

        subject.restore
      end

      it "runs the uploader" do
        expect(uploader).to receive(:run)

        subject.restore
      end
    end
  end

  describe "#reconnect" do
    it "disconnects from the server" do
      expect(imap).to receive(:disconnect)

      subject.reconnect
    end

    it "causes reconnection on future access" do
      expect(Net::IMAP).to receive(:new)

      subject.reconnect
    end
  end

  describe "#disconnect" do
    it "disconnects from the server" do
      expect(imap).to receive(:disconnect)

      subject.disconnect
    end
  end
end
