require 'controlrepo'
require 'pathname'

@repo = nil
@config = nil

task :generate_fixtures do
  repo = Controlrepo.new
  raise ".fixtures.yml already exits, we won't overwrite because we are scared" if File.exists?(File.expand_path('./.fixtures.yml',repo.root))
  File.write(File.expand_path('./.fixtures.yml',repo.root),repo.fixtures)
end

task :hiera_setup do
  repo = Controlrepo.new
  current_config = repo.hiera_config
  current_config.each do |key, value|
    if value.is_a?(Hash)
      if value.has_key?(:datadir)
        current_config[key][:datadir] = Pathname.new(repo.hiera_data).relative_path_from(Pathname.new(File.expand_path('..',repo.hiera_config_file))).to_s
      end
    end
  end
  puts "Changing hiera config from \n#{repo.hiera_config}\nto\n#{current_config}"
  repo.hiera_config = current_config
end

task :generate_nodesets do
  require 'controlrepo/beaker'
  require 'net/http'
  require 'json'

  repo = Controlrepo.new

  begin
    Dir.mkdir("#{repo.root}/spec/acceptance")
    puts "Created #{repo.root}/spec/acceptance"
  rescue Errno::EEXIST
    # Do nothing, this is okay
  end

  begin
    Dir.mkdir("#{repo.root}/spec/acceptance/nodesets")
    puts "Created #{repo.root}/spec/acceptance/nodesets"
  rescue Errno::EEXIST
    # Do nothing, this is okay
  end

  facts = repo.facts
  facts.each do |fact_set|
    boxname = Controlrepo_beaker.facts_to_vagrant_box(fact_set)
    platform = Controlrepo_beaker.facts_to_platform(fact_set)
    response = Net::HTTP.get(URI.parse("https://atlas.hashicorp.com/api/v1/box/#{boxname}"))
    url = 'URL goes here'

    unless response =~ /404 Not Found/
      box_info = JSON.parse(response)
      box_info['current_version']['providers'].each do |provider|
        if provider['name'] == 'virtualbox'
          url = provider['original_url']
        end
      end
    end

    # Use an ERB template to write the files
    template_dir = File.expand_path('../../templates',File.dirname(__FILE__))
    fixtures_template = File.read(File.expand_path('./nodeset.yaml.erb',template_dir))
    output_file = File.expand_path("spec/acceptance/nodesets/#{fact_set['fqdn']}.yml",repo.root)
    if File.exists?(output_file) == false
      File.write(output_file,ERB.new(fixtures_template, nil, '-').result(binding))
      puts "Created #{output_file}"
    else
      puts "#{output_file} already exists, not going to overwrite because scared"
    end
  end
end

task :controlrepo_autotest_prep do
  require 'controlrepo/testconfig'
  @repo = Controlrepo.new
  @config = Controlrepo::TestConfig.new("#{@repo.spec_dir}/controlrepo.yaml")

  binding.pry
  # Deploy r10k to a temp dir
  #@config.r10k_deploy_local(@repo)

  # Create the other directories we need
  FileUtils.mkdir_p("#{@repo.tempdir}/spec/classes")
  FileUtils.mkdir_p("#{@repo.tempdir}/spec/acceptance/nodesets")

  # Copy our nodesets over
  FileUtils.cp_r("#{@repo.spec_dir}/acceptance/nodesets","#{@repo.tempdir}/spec/acceptance")

  # Create the Rakefile so that we can take advantage of the existing tasks
  @config.write_rakefile(@repo.tempdir, "spec/classes/**/*_spec.rb")

  # Create spec_helper.rb
  @config.write_spec_helper("#{@repo.tempdir}/spec",@repo)

  # Create spec_helper_accpetance.rb
  @config.write_spec_helper_acceptance("#{@repo.tempdir}/spec",@repo)

  # Deduplicate and write the tests (Spec and Acceptance)
  Controlrepo::Test.deduplicate(@config.tests).each do |test|
    @config.write_spec_test("#{@repo.tempdir}/spec/classes",test)
    @config.write_acceptance_test("#{@repo.tempdir}/spec/acceptance",test)
  end

  # Parse the current hiera config, modify, and write it to the temp dir
  hiera_config = @repo.hiera_config
  hiera_config.each do |setting,value|
    if value.is_a?(Hash)
      if value.has_key?(:datadir)
        hiera_config[setting][:datadir] = "#{@repo.temp_environmentpath}/#{@config.environment}/#{value[:datadir]}"
      end
    end
  end
  File.write("#{@repo.temp_environmentpath}/#{@config.environment}/hiera.yaml",hiera_config.to_yaml)

  binding.pry
end

task :controlrepo_autotest_spec do
  # TODO: Look at how this outputs and see if it needs to be improved
  system('rake spec_standalone',@repo.tempdir)
end

task :controlrepo_spec => [
  :controlrepo_autotest_prep,
  :controlrepo_autotest_spec
  ]

task :r10k_deploy_local do
  require 'controlrepo/testconfig'
  @repo = Controlrepo.new
  @config = Controlrepo::TestConfig.new("#{repo.spec_dir}/controlrepo.yaml")

  # Deploy r10k to a temp dir
  config.r10k_deploy_local(repo)
end

# TODO: We could use rspec's tagging abilities to choose which if the acceptance tests to run.



