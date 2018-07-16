import java.io.File

def procName = 'Validate Deployment'
procedure procName, description: 'Validates the deployment', {

    step procName,
          command: '''
        \$[/myProject/scripts/preamble]
        use EC::Plugin::Informatica;
        EC::Plugin::Informatica->new->step_validate_deploy;
        ''',
          shell: 'ec-perl'

    formalOutputParameter 'persistentFile', description: 'Output persistent file name used for validation'
}

