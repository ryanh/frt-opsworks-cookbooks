# All of this is basically the same as AWS's `unicorn::rails`, but since it
# refuses to run if the application_type is not "rails", we need to do it
# ourselves...

node[:deploy].each do |application, deploy|
  next if deploy[:application_type] != 'rack'

  opsworks_deploy_user do
    deploy_data deploy
  end

  opsworks_deploy_dir do
    user deploy[:user]
    group deploy[:group]
    path deploy[:deploy_to]
  end

  template "#{deploy[:deploy_to]}/shared/scripts/unicorn" do
    cookbook "unicorn"
    mode '0755'
    owner deploy[:user]
    group deploy[:group]
    source "unicorn.service.erb"
    variables(:deploy => deploy, :application => application)
  end

  service "unicorn_#{application}" do
    start_command "#{deploy[:deploy_to]}/shared/scripts/unicorn start"
    stop_command "#{deploy[:deploy_to]}/shared/scripts/unicorn stop"
    restart_command "#{deploy[:deploy_to]}/shared/scripts/unicorn restart"
    status_command "#{deploy[:deploy_to]}/shared/scripts/unicorn status"
    action :nothing
  end

  template "#{deploy[:deploy_to]}/shared/config/unicorn.conf" do
    cookbook "unicorn"
    mode '0644'
    owner deploy[:user]
    group deploy[:group]
    source "unicorn.conf.erb"
    variables(
      :deploy => deploy,
      :application => application,
      :environment => OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
    )
  end

  # Steal the database.yml template from the opsworks rails cookbook
  template "#{deploy[:deploy_to]}/shared/config/database.yml" do
    source "database.yml.erb"
    cookbook "rails"
    mode "0660"
    group deploy[:group]
    owner deploy[:user]
    variables(database: deploy[:database], environment: deploy[:rack_env])

    notifies :run, "execute[restart Sinatra application #{application}]"

    only_if do
      deploy[:database][:host].present? && File.directory?("#{deploy[:deploy_to]}/shared/config/")
    end
  end

  include_recipe "nginx"
end
