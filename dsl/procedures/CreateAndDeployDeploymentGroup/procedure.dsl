import java.io.File

def procName = 'Create and Deploy Deployment Group'
procedure procName, description: 'Creates and Deploys a new Deployment Group', {

    step procName,
          command: '''
        \$[/myProject/scripts/preamble]
        use EC::Plugin::Informatica;
        EC::Plugin::Informatica->new->step_deploy_deployment_group;
        ''',
          shell: 'ec-perl'

    formalOutputParameter 'controlFilePath', description: 'Control File Path'
}

