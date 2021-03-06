package EC::Plugin::Informatica;

use strict;
use warnings;
use Data::Dumper;
use base qw(EC::Plugin::Core);
use File::Temp qw(tempfile);
use Cwd qw(getcwd);
use JSON;
use File::Spec;


sub step_deploy_deployment_group {
    my ($self) = @_;

    my $parameters = $self->get_params_as_hashref(qw/config
        deploymentGroupName
        deploymentGroupType
        queryName
        queryType
        controlFileContents
        controlFilePath
        additionalOptionsCreate
        additionalOptionsDeploy
        updateAction
    /);
    my $config = $self->get_config($parameters->{config});
    $self->connect;
    eval {
        my $exists = $self->deployment_group_exists($parameters->{deploymentGroupName});
        if ($exists && $parameters->{updateAction} eq 'fail') {
            $self->bail_out("Deployment Group $parameters->{deploymentGroupName} already exists");
        }
        if (!$exists) {
            $self->summary('Deployment Group does not exist');
            $self->logger->info(qq{Deployment Group $parameters->{deploymentGroupName} does not exist});
            $self->create_deployment_group($parameters);
            $self->success("Deployment Grop has been created");
        }
        $self->deploy_deployment_group($parameters);
        $self->success("Deployment Group has been deployed");
        $self->disconnect;
        1;
    } or do {
        my $err = $@;
        $self->disconnect;
        $self->bail_out("Failed to deploy deployment group:" . $err);
    };
}


sub step_run_pmrep {
    my ($self) = @_;

    my $parameters = $self->get_params_as_hashref(qw/
        config
        commandName
        additionalOptions
        credential
    /);
    my $config = $self->get_config($parameters->{config});
    $self->connect;

    my $map = {};

    if ($parameters->{credential}) {
        my $xpath = $self->ec->getFullCredential($parameters->{credential});
        my $user_name = $xpath->findvalue('//userName')->string_value;
        my $password = $xpath->findvalue('//password')->string_value;
        $map = {username => 'n', password => 'x'};
        $parameters->{username} = $user_name;
        $parameters->{password} = $password;
        push @{$self->{safe_values}}, $password;
    }

    my $result = $self->run_pmrep_command($parameters->{commandName},
        $map, $parameters,
        additionalOptions => $parameters->{additionalOptions}
    );
    $self->logger->info("STDOUT: $result->{stdout}");
    $self->logger->info("CODE: $result->{code}");
    $self->logger->info("STDERR: $result->{stderr}");
    if ($result->{stderr}) {
        $self->ec->setOutputParameter('stderr', $result->{stderr});
    }
    if ($result->{stdout}) {
        my $stdout = substr(refine_output($result->{stdout}), 0, 255);
        $self->ec->setOutputParameter('stdout', $stdout);
    }

    if ($result->{code} != 0) {
        my $out = $result->{stdout} || $result->{stderr};
        $self->disconnect;
        $self->bail_out("Command Failed: $out");
    }
    $self->success("Run Command finished");
    $self->summary(refine_output($result->{stdout}));
    $self->disconnect;
}

sub step_validate_deploy {
    my ($self) = @_;

    my $parameters = $self->get_params_as_hashref(qw/
        config
        queryName
        queryType
        additionalOptions
        additionalQueryOptions
    /);
    my $config = $self->get_config($parameters->{config});
    $self->connect;

    # Execute query
    my $map = {queryName => 'q', queryType => 't', outputFile => 'u'};
    my $output_file = File::Spec->catfile(getcwd(), 'validateQuery');
    $parameters->{outputFile} = $output_file;
    eval {
        my $result = $self->run_pmrep_command("executequery", $map, $parameters,
            fail_on_error => 1,
            additionalOptions => $parameters->{additionalQueryOptions}
        );
        $self->summary("Execute Query Result: " . refine_output($result->{stdout}));
        if (! -f $output_file) {
            die "Output file is empty after the query was executed: $result->{stdout}";
        }
        $result = $self->run_pmrep_command('validate',
            {persistentInput => 'i'},
            {persistentInput => $output_file},
            fail_on_error => 1,
            additionalOptions => $parameters->{additionalOptions}
        );
        $self->success('Validation finished successfully');
        $self->summary("Validation Result: " . refine_output($result->{stdout}));
        $self->ec->setOutputParameter('persistentFile', $output_file);
        $self->disconnect;
        1;
    } or do {
        my $err = $@;
        $self->disconnect;
        $self->bail_out("Failed to validate: $err");
    };
}

sub step_rollback_deployment {
    my ($self) = @_;

    my $parameters = $self->get_params_as_hashref(qw/
        config
        deploymentGroupName
        deployRunNumber
    /);
    my $config = $self->get_config($parameters->{config});
    $self->connect;
    eval {
        my $result = $self->run_pmrep_command('rollbackdeployment',
            {deploymentGroupName => 'p', deployRunNumber => 't'},
            $parameters, fail_on_error => 1
        );
        $self->success('Rollback finished successfully');
        $self->summary("Rolled back: " . refine_output($result->{stdout}));
        $self->disconnect;
        1;
    } or do {
        my $err = $@;
        $self->disconnect;
        $self->bail_out("Failed to roll back: $err");
    };
}

sub step_register_local_repository {
    my ($self) = @_;

    my $parameters = $self->get_params_as_hashref(qw/
        config
        localRepositoryName
        credential
        securityDomain
        domainName
        portalHostname
        portalPortNumber
    /);
    my $config = $self->get_config($parameters->{config});
    $self->connect;

    my $map = {
        localRepositoryName => 'r',
        securityDomain => 's',
        domainName => 'd',
        portalHostname => 'h',
        portalPortNumber => 'o'
    };

    if ($parameters->{credential}) {
        my $xpath = $self->ec->getFullCredential($parameters->{credential});
        my $user_name = $xpath->findvalue('//userName')->string_value;
        my $password = $xpath->findvalue('//password')->string_value;
        $parameters->{username} = $user_name;
        $parameters->{password} = $password;
        push @{$self->{safe_values}}, $password;
        $map->{username} = 'n';
        $map->{password} = 'x';
    }

    eval {
        my $result = $self->run_pmrep_command('register',
            $map,
            $parameters, fail_on_error => 1
        );
        $self->summary("Registered Local Repository: " . refine_output($result->{stdout}));
        $self->disconnect;
        1;
    } or do {
        my $err = $@;
        $self->disconnect;
        $self->bail_out("Failed to register local repository: " . refine_output($err));
    };
}

sub after_init_hook {
    my ($self, %params) = @_;

    $self->{plugin_name} = '@PLUGIN_NAME@';
    $self->{project_name} = '$[/myProject/projectName]';
    $self->{plugin_key} = '@PLUGIN_KEY@';
    $self->{_credentials} = {};
    $self->{prefix} = 'ecp_informatica';
    print "Using plugin $self->{plugin_name}\n";
    $self->debug_level(1);
}

sub safe_cmd {
    my ($self, $cmd) = @_;

    my $config = $self->get_config;
    my $safe_values = $self->{safe_values} || [];
    my $re = join('|', map { quotemeta $_ } @$safe_values);
    $cmd =~ s/$re/*****/g;
    return $cmd;
}

sub get_config {
    my ($self, $config_name) = @_;

    if ($self->{config}) {
        return $self->{config};
    }
    $config_name or die "No config name is provided";

    my $credentials = $self->get_credentials($config_name => {
        userName => 'username',
        password => 'password',
        ecp_informatica_pmrepPath => 'pmrep',
        ecp_informatica_repoName => 'repoName',
        ecp_informatica_domainName => 'domainName',
        ecp_informatica_portalHostname => 'portalHostname',
        ecp_informatica_portalPortNumber => 'portalPortNumber',
        ecp_informatica_userSecurityDomain => 'userSecurityDomain',
        debugLevel => 'debugLevel',
        ecp_informatica_additionalOptions => 'additionalOptions',
    }, 'ec_plugin_cfgs');
    $self->{config} = $credentials;
    push @{$self->{safe_values}}, $credentials->{password};
    $self->logger->level($credentials->{debugLevel});
    return $credentials;
}

sub connect {
    my ($self) = @_;

    my $config = $self->get_config;
    my @command = ();
    push @command, $config->{pmrep};
    push @command, 'connect';

# Usage: connect
#                -r <repository_name>
#                {-d <domain_name> |
#                 {-h <portal_host_name>
#                  -o <portal_port_number>}}
#                [{-n <user_name>
#                 [-s <user_security_domain>]
#                  [-x <password> |
#                   -X <password_environment_variable>]} |
#                -u (connect without user in kerberos mode)]
#                [-t <client_resilience>]

    my $map = {
        username => 'n',
        password => 'x',
        repoName => 'r',
        portalHostname => 'h',
        portalPortNumber => 'o',
        userSecurityDomain => 's'
    };
    eval {
        $self->run_pmrep_command('connect', $map, $config, fail_on_error => 1, additionalOptions => $config->{additionalOptions});
        1;
    } or do {
        $self->bail_out("Connection Failed: $@");
    };
}


sub disconnect {
    my ($self) = @_;

    eval {
        my $result = $self->run_pmrep_command('cleanup', {}, {}, fail_on_error => 1);
        $self->logger->info("Disconnected successfully: " . refine_output($result->{stdout}));
        1;
    } or do {
        $self->bail_out('Failed to disconnect: ' . $@);
    };
}

sub deployment_group_exists {
    my ($self, $name) = @_;

    my $result = $self->run_pmrep_command("listobjects", {type => 'o'}, {type => 'deploymentgroup'}, fail_on_error => 1);
    my @lines = split(/\n/, $result->{stdout});
    for my $line (@lines) {
        chomp $line;
        next unless $line =~ /deployment_group\s(.+)/;
        my $deployment_group_name = $1;
        $deployment_group_name =~ s/^\s+//;
        $deployment_group_name =~ s/\s+$//;
        $self->logger->debug("Found Deployment Group: $deployment_group_name");
        if ($deployment_group_name eq $name) {
            return 1;
        }
    }

    return 0;
}


sub create_deployment_group {
    my ($self, $params) = @_;

    my $map = {
        deploymentGroupName => 'p',
        deploymentGroupType => 't',
        queryName => 'q',
        queryType => 'u',
    };
    my $result = $self->run_pmrep_command('createdeploymentgroup',
        $map, $params,
        fail_on_error => 1,
        additionalOptions => $params->{additionalOptionsCreate}
    );
    $self->logger->info("Deployment Group has been created");
    $self->summary("Create Deployment Group result: " . refine_output($result->{stdout}));
}

sub deploy_deployment_group {
    my ($self, $params) = @_;

    # Control File preparation
    my $control_file_path = $params->{controlFilePath};
    unless($control_file_path) {
        $control_file_path = $self->save_control_file($params->{controlFileContents});
    }
    # Run Command
    my $map = {
        deploymentGroupName => 'p',
        controlFilePath => 'c',
        repoName => 'r',
        username => 'n',
        password => 'x',
        domainName => 'd',
        portalHostname => 'h',
        portalPortNumber => 'o'
    };

    my $config = $self->get_config;
    $params = {%$params, %$config};
    $params->{controlFilePath} = $control_file_path;

# Usage: deploydeploymentgroup
#                              -p <deployment_group_name>
#                              -c <control_file_name>
#                              -r <target_repository_name>
#                              [-n <target_repository_user_name>
#                              [-s <target_repository_user_security_domain>]
#                               [-x <target_repository_password> |
#                                -X <target_repository_password_environment_variable>]
#                               [-d <target_domain_name> |
#                                {-h <target_portal_host_name>
#                                 -o <target_portal_port_number>}]] (only if target is in a different domain)
#                              [-l <log_file_name>]

    my $result = $self->run_pmrep_command('deploydeploymentgroup', $map, $params,
        fail_on_error => 1, additionalOptions => $params->{additionalOptionsDeploy}
    );
    $self->logger->info("Deployment Group has been deployed");
    $self->ec->setOutputParameter('controlFilePath', $control_file_path);
    $self->summary("Deploy Deployment Group result: " . refine_output($result->{stdout}));
}

sub save_control_file {
    my ($self, $content) = @_;

    my $cwd = getcwd();
    my $path = File::Spec->catfile($cwd, 'controlFile.xml');
    open my $fh, ">$path" or die "Cannot open $path for reading: $!";
    print $fh $content;
    close $fh;
    return $path;
}

sub run_pmrep_command {
    my ($self, $cmd, $map, $parameters, %options) = @_;

    $map ||= {};
    $parameters ||= {};
    my $config = $self->get_config;
    my @command = ();
    push @command, $config->{pmrep};
    push @command, $cmd;

    for my $key (keys %$map) {
        if ($parameters->{$key}) {
            my $option = $map->{$key};
            push @command, "-$option", qq{"$parameters->{$key}"};
        }
    }

    my $command = join(' ', @command);
    if ($options{additionalOptions}) {
        $command .= ' ' . $options{additionalOptions};
    }
    my $result = $self->run_command($command);
    $self->logger->debug($result);
    if ($options{fail_on_error} && $result->{code} != 0) {
        my $out = $result->{stdout} || $result->{stderr};
        $out = refine_output($out);
        die $out . "\n";
    }
    return $result;
}

sub refine_output {
    my ($output) = @_;

    my @lines = grep { $_  && $_!~ /Informatica\(r\)|Copyright|See patents/} split(/\n+/, $output);
    return join("\n", @lines);
}

sub summary {
    my ($self, $summary) = @_;
    $self->logger->info($summary);
    $self->ec->setProperty('/myJobStep/summary', $summary);
}

1;
