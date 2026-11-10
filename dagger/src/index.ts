import { dag, object, func, Directory, Socket } from "@dagger.io/dagger";

@object()
export class UptimeMonitor {
  @func()
  async deployApp(src: Directory, sock: Socket, hostPath: string): Promise<string> {
    return this.runSh(src, sock, hostPath, "sh scripts/deploy-app.sh");
  }

  @func()
  async deployMonitoring(src: Directory, sock: Socket, hostPath: string): Promise<string> {
    return this.runSh(src, sock, hostPath, "sh scripts/deploy-monitoring.sh");
  }

  @func()
  async configureGrafana(src: Directory, sock: Socket, hostPath: string): Promise<string> {
    return this.runSh(src, sock, hostPath, "sh scripts/configure-grafana.sh");
  }

  @func()
  async deployAll(src: Directory, sock: Socket, hostPath: string): Promise<string> {
    const out1 = await this.deployApp(src, sock, hostPath);
    const out2 = await this.deployMonitoring(src, sock, hostPath);
    const out3 = await this.configureGrafana(src, sock, hostPath);
    const out4 = await this.runSh(src, sock, hostPath, "sh scripts/validate.sh");
    return `=== deploy-app ===\n${out1}\n=== deploy-monitoring ===\n${out2}\n=== configure-grafana ===\n${out3}\n=== validation ===\n${out4}`;
  }

  @func()
  async chaosTest(src: Directory, sock: Socket, hostPath: string): Promise<string> {
    return this.runSh(src, sock, hostPath, "sh scripts/chaos.sh");
  }

  private async runSh(src: Directory, sock: Socket, hostPath: string, command: string): Promise<string> {
    const ctr = dag
      .container()
      .from("docker:27-cli")
      .withUnixSocket("/var/run/docker.sock", sock)
      .withMountedDirectory(hostPath, src)
      .withWorkdir(hostPath)
      .withExec(["sh", "-c", command + " 2>&1"]);
    return ctr.stdout();
  }
}
