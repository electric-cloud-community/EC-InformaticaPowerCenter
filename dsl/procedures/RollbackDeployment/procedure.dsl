import java.io.File

def procName = 'Rollback Deployment'
procedure procName, description: 'Rolls the specified deployment back', {

    step procName,
          command: '''
        \$[/myProject/scripts/preamble]
        use EC::Plugin::Informatica;
        EC::Plugin::Informatica->new->step_rollback_deployment;
        ''',
          shell: 'ec-perl'
}

