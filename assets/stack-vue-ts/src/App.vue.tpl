<template>
  <main class="scaffold-home">
    <h1>{{TITLE}}</h1>
    <p>{{DESC}}</p>
    <!-- 【待填】首个页面/视图接入后，把这里换成 router-view（App.vue 只做布局与过渡） -->
  </main>
</template>

<script setup lang="ts">
// 根组件：只负责布局与主题容器，页面内容放 views/ 下按路由挂载
</script>

<style>
html,
body,
#app {
  width: 100%;
  height: 100%;
  margin: 0;
  padding: 0;
}
</style>
