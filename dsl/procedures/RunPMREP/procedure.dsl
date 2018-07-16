import java.io.File

def procName = 'Run PMREP'
procedure procName, description: 'Runs the specified PMREP command', {

    step procName,
          command: '''
        \$[/myProject/scripts/preamble]
        use EC::Plugin::Informatica;
        EC::Plugin::Informatica->new->step_run_pmrep;
        ''',
          shell: 'ec-perl'

    formalOutputParameter 'stdout', description: 'Command stdout'
    formalOutputParameter 'stderr', description: 'Command stderr'
}

