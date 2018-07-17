import java.io.File

def procName = 'Register Local Repository'
procedure procName, description: 'Registers a local repository', {

    step procName,
          command: '''
        \$[/myProject/scripts/preamble]
        use EC::Plugin::Informatica;
        EC::Plugin::Informatica->new->step_register_local_repository;
        ''',
          shell: 'ec-perl'
}

