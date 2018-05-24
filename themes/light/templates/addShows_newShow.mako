<%inherit file="/layouts/main.mako"/>
<%!
    import json

    from medusa import app
    from medusa.indexers.indexer_api import indexerApi
    from medusa.indexers.indexer_config import indexerConfig

    from six import iteritems, text_type as str
%>
<%block name="scripts">
<script type="text/javascript" src="js/add-show-options.js?${sbPID}"></script>
<script type="text/javascript" src="js/blackwhite.js?${sbPID}"></script>
<script src="js/lib/frisbee.min.js"></script>
<script src="js/lib/vue-frisbee.min.js"></script>
<script src="js/vue-submit-form.js"></script>
<script>
window.app = {};
const startVue = () => {
    window.app = new Vue({
        el: '#vue-wrap',
        metaInfo: {
            title: 'New Show'
        },
        data() {
            return {
                // @TODO: Fix Python conversions
                formwizard: null,
                skipShow: '',
                otherShows: ${json.dumps(other_shows)},

                // Show Search
                searchRequest: null,
                searchStatus: '',
                firstSearch: false,
                searchResults: [],
                <%
                    valid_indexers = {
                        '0': {
                            'name': 'All Indexers'
                        }
                    }
                    valid_indexers.update({
                        str(i): {
                            'name': v['name'],
                            'showUrl': v['show_url'],
                            'icon': v['icon'],
                            'identifier': v['identifier']
                        }
                        for i, v in iteritems(indexerConfig)
                    })
                %>
                indexers: ${json.dumps(valid_indexers)},
                indexerTimeout: ${app.INDEXER_TIMEOUT},
                validLanguages: ${json.dumps(indexerApi().config['valid_languages'])},
                nameToSearch: ${json.dumps(default_show_name)},
                indexerId: ${provided_indexer or 0},
                indexerLanguage: ${json.dumps(app.INDEXER_DEFAULT_LANGUAGE)},

                // Provided info
                providedInfo: {
                    use: ${json.dumps(use_provided_info)},
                    seriesId: ${provided_indexer_id},
                    seriesName: ${json.dumps(provided_indexer_name)},
                    seriesDir: ${json.dumps(provided_show_dir)},
                    indexerId: ${provided_indexer},
                    indexerLanguage: 'en',

                    ## use: true,
                    ## seriesId: 1234,
                    ## seriesName: 'Show Name',
                    ## seriesDir: 'C:\\TV\\Show Name',
                },

                sanitizedNameCache: {},

                selectedRootDir: '',
                whichSeries: ''
            };
        },
        mounted() {
            const init = () => {
                this.$watch('formwizard.currentsection', newValue => {
                    if (newValue === 0 && this.$refs.nameToSearch) {
                        this.$refs.nameToSearch.focus();
                    }
                });

                this.updateBlackWhiteList();
                const { providedInfo } = this;
                const { use, seriesId, seriesDir } = providedInfo;
                if (use && seriesId !== 0 && seriesDir.length !== 0) {
                    goToStep(3);
                }

                setTimeout(() => {
                    if (this.$refs.nameToSearch) {
                        this.$refs.nameToSearch.focus();

                        if (this.nameToSearch.length !== 0) {
                            this.searchIndexers();
                        }
                    }
                }, this.formwizard.setting.revealfx[1]);
            };

            /* JQuery Form to Form Wizard- (c) Dynamic Drive (www.dynamicdrive.com)
            *  This notice MUST stay intact for legal use
            *  Visit http://www.dynamicdrive.com/ for this script and 100s more. */
            // @TODO: we need to move to real forms instead of this

            const goToStep = num => {
                $('.step').each((idx, step) => {
                    if ($.data(step, 'section') + 1 === num) {
                        $(step).click();
                    }
                });
            }

            this.formwizard = new formtowizard({ // eslint-disable-line new-cap, no-undef
                formid: 'addShowForm',
                revealfx: ['slide', 300],
                oninit: init
            });

            $(document.body).on('change', 'select[name="quality_preset"]', () => {
                this.$nextTick(() => this.formwizard.loadsection(2));
            });

            $(document.body).on('change', '#anime', () => {
                this.updateBlackWhiteList();
                this.$nextTick(() => this.formwizard.loadsection(2));
            });
        },
        computed: {
            selectedSeries() {
                const { searchResults, whichSeries } = this;
                if (searchResults.length === 0) return null;
                return searchResults.find(s => s.identifier === whichSeries);
            },
            showName() {
                const { whichSeries, providedInfo, selectedSeries } = this;
                // If we provided a show, use that
                if (providedInfo.use && providedInfo.seriesName.length !== 0) return providedInfo.seriesName;
                // If they've picked a radio button then use that
                if (selectedSeries !== null) return selectedSeries.seriesName;
                // Not selected / not searched
                return '';
            },
            addButtonDisabled() {
                const { whichSeries, selectedRootDir, providedInfo } = this;
                if (providedInfo.use) return providedInfo.seriesDir.length === 0 || providedInfo.seriesId === 0;
                return selectedRootDir.length === 0 || whichSeries === '';
            },
            spinnerSrc() {
                const themeSpinner = MEDUSA.config.themeSpinner;
                if (themeSpinner === undefined) return '';
                return 'images/loading32' + themeSpinner + '.gif';
            }
        },
        asyncComputed: {
            async showPath() {
                const { selectedRootDir, showName, providedInfo } = this;

                let showPath;
                // If we provided a show path, use that
                if (providedInfo.use && providedInfo.seriesDir.length !== 0) {
                    showPath = providedInfo.seriesDir;
                // If we have a root dir selected, figure out the path
                } else if (selectedRootDir.length !== 0) {
                    let sepChar;
                    if (selectedRootDir.indexOf('\\') > -1) {
                        sepChar = '\\';
                    } else if (selectedRootDir.indexOf('/') > -1) {
                        sepChar = '/';
                    } else {
                        sepChar = '';
                    }

                    showPath = selectedRootDir;
                    if (showPath.slice(-1) !== sepChar) {
                        showPath += sepChar;
                    }
                    showPath += '<i>||</i>' + sepChar;
                } else {
                    return 'unknown dir';
                }

                // If we have a show name then sanitize and use it for the dir name
                if (showName.length > 0) {
                    let sanitizedName = this.sanitizedNameCache[showName];
                    if (sanitizedName === undefined) {
                        const params = {
                            name: showName
                        };
                        const { data } = await api.get('internal/sanitizeFileName', { params });
                        sanitizedName = data.sanitized;
                        this.sanitizedNameCache[showName] = sanitizedName;
                    }
                    return showPath.replace('||', this.sanitizedNameCache[showName]);
                // If not then it's unknown
                } else {
                    return showPath.replace('||', '??');
                }
            }
        },
        methods: {
            vueSubmitForm,
            submitForm() {
                // If they haven't picked a show or a root dir don't let them submit
                if (this.addButtonDisabled) {
                    this.$snotify.warning('You must choose a show and a parent folder to continue.');
                    return;
                }
                generateBlackWhiteList(); // eslint-disable-line no-undef
                return this.$nextTick(() => this.vueSubmitForm('addShowForm'));
            },
            submitFormSkip() {
                this.skipShow = '1';
                return this.$nextTick(() => this.vueSubmitForm('addShowForm'));
            },
            rootDirsUpdated(rootDirs) {
                this.selectedRootDir = rootDirs.length === 0 ? '' : rootDirs.find(rd => rd.selected).path;
            },
            async searchIndexers() {
                let { nameToSearch, indexerLanguage, indexerId, indexerTimeout, indexers } = this;

                if (nameToSearch.length === 0) return;

                if (this.searchRequest) {
                    this.searchRequest.abort();
                }

                this.whichSeries = '';
                this.searchResults = [];

                // Get the language name
                const indexerLanguageSelect = this.$refs.indexerLanguage.$el;
                const indexerLanguageName = indexerLanguageSelect[indexerLanguageSelect.selectedIndex].text;

                const searchingFor = '<b>' + nameToSearch + '</b> on ' + indexers[indexerId].name + ' in ' + indexerLanguageName;
                this.searchStatus = 'Searching ' + searchingFor + '...';

                this.$nextTick(() => this.formwizard.loadsection(0)); // eslint-disable-line no-use-before-define

                const options = {
                    body: {
                        search_term: nameToSearch, // eslint-disable-line camelcase
                        lang: indexerLanguage,
                        indexer: indexerId
                    },
                    // timeout: indexerTimeout * 1000
                };
                const response = await this.$http.get('addShows/searchIndexersForShowName', options);
                if (response.ok === false) {
                    this.searchStatus = 'Search timed out, try again or try another indexer';
                    return;
                }
                data = JSON.parse(response.body);

                this.searchStatus = '';

                const languageId = data.langid;
                this.searchResults = data.results
                    .map(result => {
                        // Compute whichSeries value
                        // whichSeries = result.join('|')

                        // Unpack result items 0 through 6 (Array)
                        let [ indexerName, indexerId, indexerShowUrl, seriesId, seriesName, premiereDate, network ] = result;

                        identifier = [indexers[indexerId].identifier, seriesId].join('')

                        // Append seriesId to indexer show url
                        indexerShowUrl += seriesId;
                        // For now only add the languageId id to the tvdb url, as the others might have different routes.
                        if (languageId && languageId !== '' && indexerId === 1) {
                            indexerShowUrl += '&lid=' + languageId
                        }

                        // Discard 'N/A' and '1900-01-01'
                        const filter = string => ['N/A', '1900-01-01'].includes(string) ? '' : string;
                        premiereDate = filter(premiereDate);
                        network = filter(network);

                        indexerIcon = 'images/' + indexers[indexerId].icon;

                        return {
                            identifier,
                            // whichSeries,
                            indexerName,
                            indexerId,
                            indexerShowUrl,
                            indexerIcon,
                            seriesId,
                            seriesName,
                            premiereDate,
                            network
                        };
                    });

                if (this.searchResults.length !== 0) {
                    // Select the first result
                    this.whichSeries = this.searchResults[0].identifier;
                }

                this.firstSearch = true;

                this.$nextTick(() => {
                    this.formwizard.loadsection(0); // eslint-disable-line no-use-before-define
                });
                /*this.searchRequest = $.ajax({
                    url: 'addShows/searchIndexersForShowName',
                    data: {
                        search_term: nameToSearch, // eslint-disable-line camelcase
                        lang: indexerLanguage,
                        indexer: indexerId
                    },
                    timeout: indexerTimeout * 1000,
                    dataType: 'json',
                    error() {
                        this.searchStatus = 'Search timed out, try again or try another indexer';
                    }
                }).done(data => {
                });*/
            },
            updateBlackWhiteList() {
                // Currently requires jQuery
                if ($ === undefined) return;
                $.updateBlackWhiteList(this.showName);
            }
        }
    });
};
</script>
</%block>
<%block name="content">
<vue-snotify></vue-snotify>
<h1 class="header">New Show</h1>
<div class="newShowPortal">
    <div id="config-components">
        <ul><li><app-link href="#core-component-group1">Add New Show</app-link></li></ul>
        <div id="core-component-group1" class="tab-pane active component-group">
            <div id="displayText">Adding show <b v-html="showName"></b> into <b v-html="showPath"></b></div>
            <br>
            <form id="addShowForm" method="post" action="addShows/addNewShow" redirect="/home" accept-charset="utf-8">
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Find a show on selected indexer(s)</legend>
                    <div v-if="providedInfo.use" class="stepDiv">
                        Show retrieved from existing metadata:
                        <app-link :href="indexers[providedInfo.indexerId].showUrl + providedInfo.seriesId">
                            <b>{{ providedInfo.seriesName }}</b>
                        </app-link>
                        <input type="hidden" name="indexer_lang" :value="providedInfo.indexerLanguage" />
                        <input type="hidden" name="whichSeries" :value="providedInfo.seriesId" />
                        <input type="hidden" name="providedIndexer" :value="providedInfo.indexerId" />
                        <input type="hidden" :value="providedInfo.seriesName" />
                    </div>
                    <div v-else class="stepDiv">
                        <input type="text" v-model.trim="nameToSearch" ref="nameToSearch" @keyup.enter="searchIndexers" class="form-control form-control-inline input-sm input350"/>
                        &nbsp;&nbsp;
                        <language-select @update-language="indexerLanguage = $event" ref="indexerLanguage" name="indexer_lang" :language="indexerLanguage" :available="validLanguages.join(',')" class="form-control form-control-inline input-sm"></language-select>
                        <b>*</b>
                        &nbsp;
                        <select name="providedIndexer" v-model.number="indexerId" class="form-control form-control-inline input-sm">
                            <option v-for="(indexer, indexerId) in indexers" :value="indexerId">{{indexer.name}}</option>
                        </select>
                        &nbsp;
                        <input class="btn-medusa btn-inline" type="button" value="Search" @click="searchIndexers" />

                        <p style="padding: 20px 0;">
                            <b>*</b> This will only affect the language of the retrieved metadata file contents and episode filenames.<br />
                            This <b>DOES NOT</b> allow Medusa to download non-english TV episodes!
                        </p>

                        <div v-if="!firstSearch || searchStatus !== ''">
                            <img v-if="searchStatus.startsWith('Searching')" :src="spinnerSrc" height="32" width="32" />
                            <span v-html="searchStatus"></span>
                        </div>
                        <div v-else class="search-results">
                            <legend class="legendStep">Search Results:</legend>
                            <table v-if="searchResults.length !== 0" class="search-results">
                                <thead>
                                    <tr>
                                        <th></th>
                                        <th>Show Name</th>
                                        <th class="premiere">Premiere</th>
                                        <th class="network">Network</th>
                                        <th class="indexer">Indexer</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="result in searchResults" @click="whichSeries = result.identifier" :class="{ selected: whichSeries === result.identifier }">
                                        <td style="text-align: center; vertical-align: middle;">
                                            <input v-model="whichSeries" type="radio" :value="result.identifier" name="whichSeries" />
                                        </td>
                                        <td>
                                            <app-link :href="result.indexerShowUrl" title="Go to the show's page on the indexer site">
                                                <b>{{ result.seriesName }}</b>
                                            </app-link>
                                        </td>
                                        <td class="premiere">{{ result.premiereDate }}</td>
                                        <td class="network">{{ result.network }}</td>
                                        <td class="indexer">
                                            {{ result.indexerName }}
                                            <img height="16" width="16" :src="result.indexerIcon" />
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            <div v-else class="no-results">
                                <b>No results found, try a different search.</b>
                            </div>
                        </div>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Pick the parent folder</legend>
                    <div v-if="providedInfo.use && providedInfo.seriesDir.length !== 0" class="stepDiv">
                        Pre-chosen Destination Folder: <b>{{providedInfo.seriesDir}}</b> <br>
                        <input type="hidden" name="fullShowPath" :value="providedInfo.seriesDir" /><br>
                    </div>
                    <div v-else class="stepDiv">
                        <root-dirs @update:root-dirs="rootDirsUpdated"></root-dirs>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Customize options</legend>
                    <div class="stepDiv">
                        <%include file="/inc_addShowOptions.mako"/>
                    </div>
                </fieldset>

                <input v-for="nextShow in otherShows" type="hidden" name="other_shows" :value="nextShow" />

                <input type="hidden" name="skipShow" :value="skipShow" />
            </form>
            <br>
            <div style="width: 100%; text-align: center;">
                <input @click.prevent="submitForm" class="btn-medusa" type="button" value="Add Show" :disabled="addButtonDisabled" />
                <input v-if="providedInfo.use && providedInfo.seriesDir.length !== 0" @click.prevent="submitFormSkip" class="btn-medusa" type="button" value="Skip Show" />
            </div>
        </div>
    </div>
</div>
</%block>
