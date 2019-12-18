pipeline {
    agent {
        docker { image 'ubuntu'
                 label 'slave02'
        }
    }
    stages {
        stage('Build') {
            steps {
                echo 'Building..222'
            }
        }
        stage('Test') {
            steps {
                echo 'Testing..333'
            }
        }
        stage('Deploy') {
            steps {
                echo 'Deploying....444'
                sh 'ls /.dockerenv'
            }
        }
    }
}