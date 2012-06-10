# encoding: utf-8
load File.expand_path( '../spec_helper.rb', File.dirname(__FILE__) )

describe Imap::Backup::Settings do

  context '#initialize' do

    it 'should fail if the config file is missing' do
      File.should_receive(:exist?).and_return(false)

      expect do
        Imap::Backup::Settings.new
      end.to raise_error(RuntimeError, /not found/)
    end

    it 'should fail if the config file permissions are too lax' do
      File.stub!(:exist?).and_return(true)

      stat = stub('File::Stat', :mode => 0644)
      File.should_receive(:stat).and_return(stat)

      expect do
        Imap::Backup::Settings.new
      end.to raise_error(RuntimeError, /Permissions.*?should be 0600/)
    end

    it 'should load the config file' do
      File.stub!(:exist?).and_return(true)

      stat = stub('File::Stat', :mode => 0600)
      File.stub!(:stat).and_return(stat)

      file = stub('file')
      File.should_receive(:open).with(%r{/.imap-backup/config.json}).and_return(file)
      JSON.should_receive(:load).with(file)

      Imap::Backup::Settings.new
    end

  end

  context '#each_account' do
    before :each do
      @account1_settings = stub('account1 settings')
      settings = {
        'accounts' => [
          @account1_settings
        ]
      }
      File.stub!(:open)
      JSON.stub!(:load).and_return(settings)
      @account = stub('Imap::Backup::Settings', :disconnect => nil)
    end

    subject { Imap::Backup::Settings.new }

    it 'should create accounts' do
      Imap::Backup::Account.should_receive(:new).with(@account1_settings).and_return(@account)
      subject.each_account {}
    end

    it 'should call the block' do
      Imap::Backup::Account.stub!(:new).and_return(@account)
      calls = 0

      subject.each_account do |a|
        calls += 1
        a.should == @account
      end
      calls.should == 1
    end

    it 'should disconnect the account' do
      Imap::Backup::Account.stub!(:new).and_return(@account)

      @account.should_receive(:disconnect)

      subject.each_account {}
    end

  end

end

